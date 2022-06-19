title = 'Crowdfuncerd Podcast'

description = [[
  A podcast in which episodes -- themes and guests -- are decided by the public, which suggests and votes with sats on what they want to see, from right inside their podcast player. The contributed money goes to the suggested guests.
]]

models = {
  {
    name = 'settings',
    display = 'Settings',
    single = true,
    fields = {
      { name = 'name', display = 'Podcast Name', required = true, type = 'string' },
      { name = 'description', display = 'Podcast Description', required = true, type = 'string' },
      { name = 'author', display = 'Author Name', type = 'string' },
      { name = 'image', display = 'Cover Image', type = 'url' },
      { name = 'website', display = 'Website', type = 'url' },
      { name = 'fallback_audio', display = 'Fallback Audio File', type = 'url' },
    }
  },
  {
    name = 'episodes',
    display = 'Episode',
    fields = {
      { name = 'title', display = 'Guests + Theme', required = true, type = 'string' },
      { name = 'file', display = 'File', type = 'url' },
      { name = 'contributions', default = 0, display = 'Contributions', type = 'msatoshi' },
    }
  }
}

actions = {
  feed = {
    handler = function (params)
      -- initial params and db fetches
      local settings = db.settings.get()
      local episodes = db.episodes.list()

      -- generate feed
      local now = os.date("%a, %d %b %y %X +0000", os.time())
      local image = ''
      if settings.image then
		image = [[
        <image>
          <url>]] .. settings.image .. [[</url>
          <title>]] .. settings.name .. [[</title>
        </image>
		<itunes:image href="]] .. settings.image .. [[" />
        ]]
      end
      local author = ''
      if settings.author then
        author = [[
          <copyright>]] .. settings.author .. [[</copyright>
          <itunes:author>]] .. settings.author .. [[</itunes:author>
        ]]
      end
      local url = params._url:sub(0, params._url:find('/feed') - 1) .. '/suggest'
      local suggest_paycode = lnurl.bech32_encode(url)
      local call_to_action = "To suggest an episode theme and guests, open this paycode on your Lightning wallet and include a comment with the title of the episode you want to see, including the names of the guests and the theme subject: "
      local description = table.concat({
        settings.description,
        call_to_action,
        suggest_paycode:lower()
      }, "\n\n")
      local encoded = table.concat({
        "<![CDATA[",
        "<p><i>" .. settings.description .. "</i></p>",
        "<p>" .. call_to_action .. "</p>",
        "<p><a href='lightning:" .. suggest_paycode:lower() .. "'>",
        "  <img src='https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=" .. suggest_paycode .. "'>",
        "</a></p>",
        "<p><a href='lightning:" .. suggest_paycode:lower() .. "'>",
        "  <code>" .. suggest_paycode:lower() .. "</code>",
        "</a></p>",
        "]]>"
      }, "")
      local feed = {[[
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:cc="http://web.resource.org/cc/" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:podcast="https://podcastindex.org/namespace/1.0" xmlns:googleplay="http://www.google.com/schemas/play-podcasts/1.0" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
	<channel>
		<atom:link href="]] .. params._url .. [[" rel="self" type="application/rss+xml"/>
		<title>]] .. settings.name .. [[</title>
		<pubDate>]] .. now .. [[</pubDate>
		<lastBuildDate>]] .. now .. [[</lastBuildDate>
		<generator>LNbits Infinity Crowdfuncerd Module</generator>
		<link>]] .. (settings.website or '') .. [[</link>
		<language>en</language>
        ]] .. image .. [[
		<description>]] .. description .. [[</description>
        <content:encoded>]] .. encoded .. [[</content:encoded>
        <itunes:summary>]] .. description .. [[</itunes:summary>
		<itunes:type>episodic</itunes:type>
        <itunes:category text="Business"></itunes:category>
        <itunes:category text="Technology"></itunes:category>
      ]]
      }

      -- go through all episodes
      for _, ep in ipairs(episodes) do
        local received = math.ceil((ep.value.contributions or 0) / 1000) .. " sat"
        local url = params._url:sub(0, params._url:find('/feed') - 1) .. '/contribute?episode=' .. ep.key
        local paycode = lnurl.bech32_encode(url)

        local title
        local call_to_action
        local file
        local filetype
        if ep.value.file == nil then
          title = "[SUGGESTION][" .. received .. "] " .. ep.value.title
          call_to_action = "Send money if you want to see this episode happen: "
          file = settings.fallback_file or 'https://example.com/nofile.mp3'
          file = file .. "?guid=" .. ep.key
          filetype = 'audio/mpeg'
        else
          title = ep.value.title
          call_to_action = "Send money if you want to donate to this episode's guests: "
          file = ep.value.file
          filetype = 'audio/mpeg' -- TODO parse mimetype from extension
        end
        local description = table.concat({
          ep.value.title,
          "Total received so far: " .. received,
          call_to_action,
          paycode:lower()
        }, "\n\n")
        local encoded = table.concat({
          "<![CDATA[",
          "<p><i>" .. ep.value.title .. "</i></p>",
          "<p>" .. call_to_action .. "</p>",
          "<p><a href='lightning:" .. paycode:lower() .. "'>",
          "  <img src='https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=" .. paycode .. "'>",
          "</a></p>",
          "<p><a href='lightning:" .. paycode:lower() .. "'>",
          "  <code>" .. paycode:lower() .. "</code>",
          "</a></p>",
          "<p>Total received so far: <b>" .. received .. "</b></p>",
          "<hr>",
          "<p>Use this paycode to suggest a new episode theme and guests:</p>",
          "<p><a href='lightning:" .. suggest_paycode:lower() .. "'>",
          "  <img src='https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=" .. suggest_paycode .. "'>",
          "</a></p>",
          "<p><a href='lightning:" .. suggest_paycode:lower() .. "'>",
          "  <code>" .. suggest_paycode:lower() .. "</code>",
          "</a></p>",
          "]]>"
        }, "")

        table.insert(feed, [[
<item>
  <guid isPermaLink="false">]] .. ep.key .. [[</guid>
  <title>]] .. title .. [[</title>
  <description>]] .. description .. [[</description>
  <content:encoded>]] .. encoded .. [[</content:encoded>
  <pubDate>]] .. ep.updated_at .. [[</pubDate>
  <enclosure]] .. ' url="' .. file .. '" type="' .. filetype .. '">' .. [[</enclosure>
  <itunes:episodeType>full</itunes:episodeType>
</item>
        ]])
      end

      table.insert(feed, "</channel></rss>")

      return {
        status = 200,
        headers = {
          ['content-type'] = 'application/rss+xml',
        },
        body = table.concat(feed, "")
      }
    end
  },
  suggest = {
    fields = {
      { name = 'amount', required = false, type = 'string' },
      { name = 'comment', required = false, type = 'string' },
    },
    handler = function (params)
      -- base stuff
      local metadata = json.encode({
        {'text/plain', 'Suggestion of a new episode. Include details on the comment.'},
        {'text/long-desc', 'Your comment should list the names of the guests first and then the theme they will be discussing, and it must be related to Bitcoin. For example: "Ruben Somsen and Zooko Wilcox talking about the advantages and disadvantages of Taro"'}
      })

      if not params.amount then
        -- return metadata
        return {
          tag = 'payRequest',
          metadata = metadata,
          minSendable = 1000000,
          maxSendable = 1000000000,
          commentAllowed = 300,
          callback = params._url -- this same URL
        }
      else
        -- make and return the invoice
        params.amount = tonumber(params.amount)
        if params.amount < 100000 then
          return { status = 'ERROR', reason = 'suggestions must include at least 1000 sat' }
        end
        if params.comment == nil or #params.comment < 100 or #params.comment > 300 then
          return { status = 'ERROR', reason = 'suggestions must include a comment describing who should be on the episode and talking about what' }
        end

        local invoice, err = wallet.create_invoice({
          description_hash = utils.sha256(metadata),
          msatoshi = params.amount,
          extra = {
            suggestion = params.comment
          }
        })
        if err then
          return { status = 'ERROR', reason = err }
        end

        return {
          routes = emptyarray(),
          pr = invoice.bolt11,
        }
      end
    end
  },
  contribute = {
    fields = {
      { name = 'episode', required = true, type = 'ref', ref = 'episodes', as = 'title' },
      { name = 'amount', required = false, type = 'string' },
    },
    handler = function (params)
      -- base stuff
      local episode = db.episodes.get(params.episode)
      local metadata = json.encode({
        {'text/plain', 'Contribution for the episode "' .. episode.title .. '" to happen.'}
      })

      if not params.amount then
        -- return metadata
        return {
          tag = 'payRequest',
          metadata = metadata,
          minSendable = 100000,
          maxSendable = 100000000,
          callback = params._url -- this same URL
        }
      else
        -- make and return the invoice
        params.amount = tonumber(params.amount)
        if params.amount < 100000 then
          return { status = 'ERROR', reason = 'you must pay at least 100 sat' }
        end

        local invoice, err = wallet.create_invoice({
          description_hash = utils.sha256(metadata),
          msatoshi = params.amount,
          extra = {
            episode = params.episode,
          },
        })
        if err then
          return { status = 'ERROR', reason = err }
        end

        return {
          routes = emptyarray(),
          pr = invoice.bolt11,
        }
      end
    end
  }
}

triggers = {
  payment_received = function (payment)
    if payment.tag ~= app.id then
      return
    end

    if payment.extra.episode then
      local episode = db.episodes.get(payment.extra.episode)
      episode.contributions = (episode.contributions or 0) + payment.amount
      db.episodes.set(payment.extra.episode, episode)
      return
    end

    if payment.extra.suggestion then
      db.episodes.add({
        title = payment.extra.suggestion,
        contributions = payment.amount
      })
    end
  end,
}
