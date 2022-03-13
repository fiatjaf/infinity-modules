title = 'SecretPodcast'

description = [[Allows you to publish a podcast feed in which each episode will be sold for an amount of satoshis.

Media must be stored somewhere else and passed as an URL, which will then be proxied through this server.

You can give a different RSS URL to each user, then they will be able to pay-to-play from inside their podcast player.]]

models = {
  {
    name = 'podcast',
    display = 'Podcast Metadata',
    single = true,
    fields = {
      { name = 'title', display = 'Title', required = true, type = 'string' },
      { name = 'description', display = 'Description', type = 'string' },
    }
  },
  {
    name = 'episode',
    display = 'Episode',
    fields = {
      { name = 'time', display = 'Published at', required = true, type = 'datetime' },
      { name = 'title', display = 'Title', required = true, type = 'string' },
      { name = 'file', display = 'Audio File URL', required = true, type = 'url' },
      { name = 'description', display = 'Description', type = 'string' },
      { name = 'price', display = 'Price', required = true, type = 'msatoshi' },
    }
  },
  {
    name = 'sale',
    display = 'Episode Sale',
    plural = 'Episodes Sold',
    fields = {
      { name = 'episode', display = 'Episode', required = true, type = 'ref', ref = 'episode', as = 'title' },
      { name = 'feed', display = 'Buyer RSS Feed ID', required = true, type = 'string' },
    }
  }
}

actions = {
  feed = {
    fields = {
      { name = 'id', required = true, type = 'string' },
    },
    handler = function (params)
      local podcast = db.podcast.get()
      local episodes = db.episode.list()
      local sales = db.sale.list({
        startkey = params.id,
        endkey = params.id .. "~"
      })

      -- make a map out of the sales so we can exclude preview episodes if they are bought
      local sales_map = {}
      for _, sale in ipairs(sales) do
        local key = sale.value.episode
        sales_map[key] = true
      end

      local items = ""

      -- add preview episodes
      for _, episode in ipairs(episodes) do
        local key = episode.key

        -- only add episodes that were not paid for, as previews
        if not sales_map[key] then
          local ep = episode.value

          local paycode = lnurl.bech32_encode(
            params._url:gsub('/feed.*', '') ..
              '/buy_episode?feed_id=' .. params.id .. '&episode=' .. key
          )
          local description = "pay to access this episode:\n\n" .. paycode .. '\n\n' .. (ep.description or '')

          items = items .. [[
    <item>
      <guid>]] .. key .. [[</guid>
      <title>]] .. ep.title .. " (preview)" .. [[</title>
      <description>]] .. description .. [[</description>
      <pubDate>]] .. os.date("%a, %d %b %y %X +0000", ep.time) .. [[</pubDate>
      <enclosure url="]] .. ep.file .. [[" type="audio/mpeg"></enclosure>
    </item>
]]
        end
      end

      -- add full episodes
      for _, sale in ipairs(sales) do
        local key = sale.value.episode
        local ep = db.episode.get(key)

        local description = "episode purchased!" .. '\n\n' .. (ep.description or '')

        items = items .. [[
    <item>
      <guid>]] .. key .. [[</guid>
      <title>]] .. ep.title .. " (purchased)" .. [[</title>
      <description>]] .. description .. [[</description>
      <pubDate>]] .. os.date("%a, %d %b %y %X +0000", ep.time + 1) .. [[</pubDate>
      <enclosure url="]] .. ep.file .. [[" type="audio/mpeg"></enclosure>
    </item>
]]
      end

      local body = [[
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>]] .. podcast.title .. [[</title>
    <description>]] .. (podcast.description or '') .. [[</description>
    <pubDate>]] .. os.date("%a, %d %b %y %X +0000", os.time()) .. [[</pubDate>
]] .. items .. [[
  </channel>
</rss>]]

      return {
        status = 200,
        headers = {
          ['content-type'] = 'application/rss+xml',
        },
        body = body
      }
    end
  },
  buy_episode = {
    fields = {
      { name = 'episode', required = true, type = 'ref', ref = 'episode', as = 'title' },
      { name = 'feed_id', required = true, type = 'string' },
    },
    handler = function (params)
      local episode = db.episode.get(params.episode)
      local metadata = json.encode({
        {'text/plain', 'buying access to the episode "' .. episode.title .. '"'}
      })

      if not params.amount then
        -- return the invoice
        return {
          tag = 'payRequest',
          metadata = metadata,
          minSendable = episode.price,
          maxSendable = episode.price,
          callback = params._url
        }
      else
        -- return metadata
        local invoice, err = wallet.create_invoice({
          description_hash = utils.sha256(metadata),
          msatoshi = episode.price,
          extra = {
            feed = params.feed_id,
            episode = params.episode,
          },
        })
        if err then
          return { status = 'ERROR', reason = err }
        end

        return {
          pr = invoice.bolt11,
          routes = emptyarray()
        }
      end
    end
  }
}

triggers = {
  payment_received = function (payment)
    if payment.tag ~= app.id or not payment.extra.feed or not payment.extra.episode then
      return
    end

    local sale_id = payment.extra.feed .. '/' .. payment.extra.episode

    db.sale.set(sale_id, {
      feed = payment.extra.feed,
      episode = payment.extra.episode,
    })
  end,
}
