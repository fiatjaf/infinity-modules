title = 'WebShop'

description = [[A generic e-commerce backend with a simple UI, to be manually tweaked for your purposes. Can be also used just as a simple API.

[Example Storefront]($extBase/)
]]

models = {
  {
    name = 'metadata',
    display = 'Metadata',
    fields = {
      { name = 'name', display = 'Shop Name', type = 'string' },
      { name = 'description', display = 'Shop Description', type = 'string' },
      { name = 'picture', display = 'Shop Picture', type = 'url' },
    },
    single = true
  },
  {
    name = 'product',
    display = 'Product',
    fields = {
      { name = 'name', display = 'Product Name', required = true, type = 'string' },
      { name = 'description', display = 'Description', type = 'string' },
      { name = 'price', type = 'currency', display = 'Price', required = true },
      { name = 'picture', display = 'Picture', type = 'url' },
    }
  },
  {
    name = 'sale',
    display = 'Sale',
    fields = {
      { name = 'product', ref = 'product', type = 'ref', required = true, as = 'name' },
      { name = 'paid', type = 'boolean', default = false },

      -- anything that identifies the buyer
      { name = 'buyer', type = 'string', required = true },
    },
    default_sort = 'paid desc'
  },
  {
    name = 'notification',
    display = 'Notification',
    fields = {
      { name = 'telegram_bot_key', display = 'Telegram Bot Key', type = 'string' },
      { name = 'telegram_chat_id', display = 'Telegram Chat ID', type = 'string' },
      { name = 'webhook', display = 'Webhook URL', type = 'url' },
    },
    single = true
  },
}

actions = {
  getmetadata = {
    handler = function ()
      return db.metadata.get()
    end,
  },
  getproducts = {
    handler = function ()
      return db.product.list()
    end,
  },
  buy = {
    fields = {
      { name = 'buyer', required = true, type = 'string' },
      { name = 'product', required = true, type = 'ref', ref = 'product', as = 'name' },
    },
    handler = function (params)
      local product = db.product.get(params.product)
      local current_price = utils.get_msats_per_fiat_unit(product.price.unit) * product.price.amount

      local key = db.sale.add({
        buyer = params.buyer,
        product = params.product,
      })

      local invoice = wallet.create_invoice({
        description = product.name .. " sold to " .. params.buyer,
        msatoshi = current_price,
        extra = {
          sale = key
        },
      })

      return {
        sale = key,
        invoice = invoice.bolt11,
      }
    end,
  }
}

triggers = {
  payment_received = function (payment)
    if payment.tag ~= app.id or not payment.extra.sale then
      return
    end

    db.sale.update(payment.extra.sale, { paid = true })
    local sale = db.sale.get(payment.extra.sale)
    local product = db.product.get(sale.product)

    -- emit event to payer
    app.emit_event('sale-paid', payment.extra.sale)

    -- send notifications
    local notification = db.notification.get()
    if notification.telegram_bot_key and notification.telegram_chat_id then
      http.post('https://api.telegram.org/bot' .. notification.telegram_bot_key .. '/sendMessage', {
        chat_id = notification.telegram_chat_id,
        parse_mode = 'HTML',
        text = [[<b>sale paid</b>: <code>]] .. payment.extra.sale .. [[</code>
<b>product</b>: <code>]] .. product.name .. [[</code>
<b>payment hash</b>: <code>]] .. payment.hash .. [[</code>
<b>amount paid</b>: <code>]] .. math.floor(payment.amount / 1000) .. [[ sats</code>
<b>buyer</b>: <code>]] .. sale.buyer .. [[</code>
        ]]
      })
    end
    if notification.webhook then
      http.post(notification.webhook, {
        sale_key = payment.extra.sale,
        sale = sale,
        product = product,
        payment = payment,
        time = os.time(),
      })
    end
  end,
  hourly = function ()
    for _, item in ipairs(db.sale.list()) do
      local olderthan1day = utils.parse_date(item.created_at) < (os.time() - 60 * 60 * 24)
      if olderthan1day and not item.value.paid then
        db.sale.delete(item.key)
      end
    end
  end,
}
