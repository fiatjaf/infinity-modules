title = 'Adfree Podcasts'

description = [[
  Given a base podcast feed and adfree episodes that match the names of existing episodes, build a new "global" feed that has the adfree episodes with LNURLs that can be paid to generate feeds with unique IDs (with the actual bought episodes).

  After the listener has already subscribed to the feed with the unique ID, regardless of having done that separately or through the purchase from the main feed, he can keep buying directly on the unique feed.
]]

models = {
  {
    name = 'settings',
    display = 'Settings',
    single = true,
    fields = {
      { name = 'base_feed', display = 'Base Podcast Feed URL', required = true, type = 'string' },
      { name = 'fallback_file', display = 'Fallback File for Unpaid Episodes', type = 'string' },
    }
  },
  {
    name = 'adfree_version',
    display = 'Episode',
    fields = {
      { name = 'title_match', display = 'Title Match', required = true, type = 'string' },
      { name = 'file', display = 'Adfree Audio File URL', required = true, type = 'url' },
      { name = 'price', display = 'Price', required = true, type = 'msatoshi' },
    }
  },
  {
    name = 'sale',
    display = 'Episode Sale',
    plural = 'Episodes Sold',
    fields = {
      { name = 'episode', display = 'Episode', required = true, type = 'ref', ref = 'adfree_version', as = 'title_match' },
      { name = 'feed', display = 'Buyer RSS Feed ID', required = true, type = 'string' },
    }
  }
}

actions = {
  feed = {
    fields = {
      { name = 'id', required = false, type = 'string' },
    },
    handler = function (params)
      -- initial params and db fetches
      local settings = db.settings.get()
      local adfree_versions = db.adfree_version.list()
      local sales = {}
      if params.id then
        -- we'll only have sold episodes if the listener has provided an id for itself
        sales = db.sale.list({
          startkey = params.id,
          endkey = params.id .. "~"
        })
      end

      -- make a map out of the adfree episodes
      local adfree_map = {}
      for _, ep in ipairs(adfree_versions) do
        adfree_map[ep.key] = ep
      end

      -- make a map out of the sales
      local sales_map = {}
      for _, sale in ipairs(sales) do
        local key = adfree_map[sale.value.episode].key
        sales_map[key] = true
      end

      -- a function to find one adfree episode that matches a normal episode
      local matches_adfree = function (feed_item)
        for _, ep in ipairs(adfree_versions) do
          if feed_item.title:match(ep.value.title_match) then
            return ep
          end
        end

        return nil
      end

      -- parse base feed
      local feed, raw_feed, err = utils.feed_parse(settings.base_feed)
      if err then
        return { error = 'failed to parse feed "' .. settings.base_feed .. '": ' .. err }
      end

      -- we'll make list of everything we have to add
      -- then at the end we put them all in a very ugly way
      local items_to_add = {}

      -- go through all episodes in the base feed
      for _, item in ipairs(feed.items) do
        -- if there is an adfree version for this, add it with a way to pay
        local adfree = matches_adfree(item)
        if adfree then
          -- if it is sold, add a new item with the adfree audio
          -- otherwise add an annoucement for the adfree version to be bought
          local title
          local description = utils.html_escape(item.description or '')
          local file
          local filetype
          if sales_map[adfree.key] then
            title = "[BOUGHT][NO ADS] " .. item.title
            description = "You've bought this episode!" .. '\n\n' .. description
            file = adfree.value.file
            filetype = 'audio/mpeg' -- TODO parse mimetype from extension
          else
            local url = params._url:sub(0, params._url:find('/feed') - 1) ..
              '/buy_episode?episode=' .. adfree.key
            if params.id then
              url = url .. '&feed_id=' .. params.id
            end
            local paycode = lnurl.bech32_encode(url)
            title = "[NO ADS] " .. item.title
            description = "Buy this episode without ads!\n\n" ..
                paycode .. '\n\n' .. description
            file = settings.fallback_file or 'https://example.com/nofile.mp3'
            file = file .. "?guid=" .. item.guid
            filetype = 'audio/mpeg'
          end

          local extra_item = [[
<item>
  <guid>]] .. "adfree_" .. item.guid .. [[</guid>
  <title>]] .. title .. [[</title>
  <description>]] .. description .. [[</description>
  <pubDate>]] .. item.published .. [[</pubDate>
  <enclosure]] .. ' url="' .. file .. '" type="' .. filetype .. '">' .. [[</enclosure>
</item>
          ]]
          table.insert(items_to_add, extra_item)
        end
      end

      -- add extra items
      local items = table.concat(items_to_add, "")
      local channel_end = raw_feed:find("</channel>")
      local body = raw_feed:sub(0, channel_end - 1) .. items .. raw_feed:sub(channel_end)

      -- replace title
      if params.id then
        local _, s = body:find("<title>")
        local e, _ = body:find("</title>")
        if s and e then
          body = body:sub(0, s) .. "[" .. params.id .. "] " .. feed.title .. body:sub(e)
        end
      end

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
      { name = 'episode', required = true, type = 'ref', ref = 'adfree_version', as = 'title_match' },
      { name = 'feed_id', required = false, type = 'string' },
    },
    handler = function (params)
      -- base stuff
      local episode = db.adfree_version.get(params.episode)
      local metadata = json.encode({
        {'text/plain', 'buying access to the episode "' .. episode.title_match .. '"'}
      })
      local feed_id = params.feed_id

      if not params.amount then
        -- return metadata
        return {
          tag = 'payRequest',
          metadata = metadata,
          minSendable = episode.price,
          maxSendable = episode.price,
          callback = params._url -- this same URL
        }
      else
        -- make and return the invoice
        local successAction

        -- each feed has an id that we use to match with the episodes paid for
        -- if there is no feed id, use a random one and let the buyer know through lnurl
        if not params.feed_id then
          feed_id = utils.random_hex(4)
        end

        -- make the invoice
        local invoice, err = wallet.create_invoice({
          description_hash = utils.sha256(metadata),
          msatoshi = episode.price,
          extra = {
            feed = feed_id,
            episode = params.episode,
          },
        })
        if err then
          return { status = 'ERROR', reason = err }
        end

        -- direct the user to replace its main feed url with their personal url
        -- using the lnurl aes successAction (with the invoice preimage)
        if not params.feed_id then
          local user_feed_url = params._url:sub(0, params._url:find('/buy_episode') - 1) ..
            '/feed?id=' .. feed_id
          local ct, iv, err = lnurl.successaction_aes(invoice.preimage, user_feed_url)
          if err then
            return {
              status = 'ERROR',
              reason = 'failed to encrypt confirmation code: ' .. err
            }
          end
          successAction = {
            tag = 'aes',
            description = "Use this as your personal feed for this podcast",
            ciphertext = ct,
            iv = iv,
          }
        end

        -- return the lnurl response with the invoice
        return {
          routes = emptyarray(),
          pr = invoice.bolt11,
          successAction = successAction
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
