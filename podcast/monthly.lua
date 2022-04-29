title = 'Podcast Monthly Subscription'

description = [[
  Like adfree, but you pay for a month of access and your entire feed gets unblocked.
]]

models = {
  {
    name = 'settings',
    display = 'Settings',
    single = true,
    fields = {
      { name = 'hidden_feed', display = 'Base Podcast Feed URL', required = true, type = 'string' },
      { name = 'monthly_price', display = 'Price for a month of access to the hidden feed', required = true, type = 'msatoshi' },
      { name = 'podcast_title', display = 'Podcast Title to be used in invoices', required = true, type = 'string' },
      { name = 'teaser_title', display = 'Fallback Teaser Episode Title for Inactive Feeds', type = 'string' },
      { name = 'teaser_description', display = 'Fallback Teaser Episode Description for Inactive Feeds', type = 'string' },
      { name = 'teaser_file', display = 'Fallback File for Inactive Feeds', type = 'string' },
    }
  },
  {
    name = 'subscriptions',
    display = 'Active Subscription',
    plural = 'Active Subscriptions',
    fields = {
      { name = 'first_payment', display = 'First Payment', required = true, type = 'datetime' },
      { name = 'total_paid', display = 'Total Paid', required = true, type = 'msatoshi' },
      { name = 'active_until', display = 'Active Until', required = true, type = 'datetime' },
    }
  }
}

actions = {
  feed = {
    fields = {
      { name = 'id', required = true, type = 'string' },
    },
    handler = function (params)
      local feed = db.subscriptions.get(params.id)
      if not feed then
        return "we don't know anything about the feed id '" .. params.id .. "'."
      end

      local settings = db.settings.get()

      if feed.active_until < os.time() then
        -- subscription expired, return a fake feed with an lnurl for purchase
        local url = params._url:sub(0, params._url:find('/feed') - 1) .. '/buy_month?feed_id=' .. params.id
        local paycode = lnurl.bech32_encode(url)

        return {
          status = 200,
          headers = {
            ['content-type'] = 'application/rss+xml',
          },
          body = [[
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>]] .. "{".. params.id .."} " .. settings.podcast_title .. " [INACTIVE]" .. [[</title>
    <description>]] .. "secret feed " .. params.id .. " for " .. settings.podcast_title .. [[</description>
    <pubDate>]] .. os.date("%a, %d %b %y %X +0000", os.time()) .. [[</pubDate>
    <item>
      <guid>teaser</guid>
      <title>]] .. (settings.teaser_title or "Buy access to this feed.") .. [[</title>
      <description>]] .. (settings.teaser_description or "Pay the invoice below to purchase one month of access to this feed: ") .. "\n\n" .. paycode .. [[</description>
      <pubDate>]] .. os.date("%a, %d %b %y %X +0000", os.time()) .. [[</pubDate>
      <enclosure url="]] .. (settings.teaser_file or "") .. [[" type="audio/mpeg"></enclosure>
    </item>
  </channel>
</rss>]]
        }
      end

      -- just proxy the hidden feed
      local body, _, err = http.get(settings.hidden_feed)
      if err then
        return "failed to fetch hidden feed: " .. err
      end

      -- replace title
      if params.id then
        local _, s = body:find("<title>")
        if s then
          body = body:sub(0, s) .. "{" .. params.id .. "} " .. body:sub(s + 1)
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
  buy_month = {
    fields = {
      { name = 'feed_id', required = false, type = 'string' },
    },
    handler = function (params)
      local settings = db.settings.get()
      local metadata = json.encode({
        {'text/plain', 'Buying one month of access to the ' .. settings.podcast_title .. ' hidden feed.'}
      })

      if not params.amount then
        -- return metadata
        return {
          tag = 'payRequest',
          metadata = metadata,
          minSendable = settings.monthly_price,
          maxSendable = settings.monthly_price,
          callback = params._url -- this same URL
        }
      else
        -- make and return the invoice
        local successAction

        -- if a feed id was not provided create a new one
        local feed_id = params.feed_id
        if not params.feed_id then
          feed_id = utils.random_hex(4)
        end

        -- make the invoice
        local invoice, err = wallet.create_invoice({
          description_hash = utils.sha256(metadata),
          msatoshi = settings.monthly_price,
          extra = {
            feed = feed_id,
          },
        })
        if err then
          return { status = 'ERROR', reason = err }
        end

        -- direct the user to replace its main feed url with their personal url
        if not params.feed_id then
          local user_feed_url = params._url:sub(0, params._url:find('/buy_month') - 1) ..
            '/feed?id=' .. feed_id
          successAction = {
            tag = 'url',
            description = "This is your hidden podcast feed. Add it to your podcast listener.",
            url = user_feed_url
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
    if payment.tag ~= app.id or not payment.extra.feed then
      return
    end

    local settings = db.settings.get()
    local one_month = 60 * 60 * 24 * 365 / 12

    local values = {
      first_payment = os.time(),
      total_paid = settings.monthly_price,
      active_until = os.time() + one_month,
    }

    local sub = db.subscriptions.get(payment.extra.feed)
    if sub then
      values.first_payment = sub.first_payment
      values.total_paid = values.total_paid + sub.total_paid
      if sub.active_until > os.time() then
        values.active_until = sub.active_until + one_month
      end
    end

    db.subscriptions.set(payment.extra.feed, values)
  end,
}
