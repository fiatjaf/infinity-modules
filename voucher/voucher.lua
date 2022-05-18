title = 'Voucher'

description = "Generate LNURL-withdraw vouchers other people can redeem."

models = {
  {
    name = 'voucher',
    display = 'Voucher',
    fields = {
      { name = "amount", type = "msatoshi", required = true },
      { name = "description", type = "string", required = true },
      { name = "used", type = "boolean", required = true, default = false },
      { name = "success", type = "boolean", required = true, default = false },
    }
  }
}

actions = {
  get_voucher_lnurl = {
    fields = {
      { name = 'voucher', type = 'ref', ref = 'voucher', as = 'description', required = true }
    },
    handler = function (params)
      return lnurl.bech32_encode(params._url:sub(
        0, params._url:find('/get_voucher_lnurl') - 1) .. '/redeem?k1=' .. params.voucher)
    end
  },
  redeem = {
    fields = {
      { name = "k1", type = "string", required = true },
      { name = "pr", type = "string", required = false },
    },
    handler = function (params)
      local key = params.k1

      local voucher, err = db.voucher.get(key)
      if not voucher then
        return { status = 'ERROR', reason = 'voucher "' .. key .. '" not found: ' .. err }
      end

      if voucher.used then
        return { status = 'ERROR', reason = 'voucher "' .. key .. '" already used' }
      end

      if not params.pr then
        return {
          tag = 'withdrawRequest',
          callback = params._url,
          k1 = key,
          defaultDescription = voucher.description,
          minWithdrawable = voucher.amount,
          maxWithdrawable = voucher.amount,
        }
      else
        local invoice = utils.decode_invoice(params.pr)
        if invoice.msatoshi ~= voucher.amount then
          return { status = 'ERROR', reason = 'amount must be ' .. voucher.amount .. ' millisatoshis' }
        end

        local err = db.voucher.update(key, { used = true })
        print("marking voucher " .. key .. " as used")
        if err ~= nil then
          return { status = 'ERROR', reason = 'database error' }
        end

        local _, err = wallet.pay_invoice({
          tag = 'voucher',
          extra = { voucher = key },
          invoice = params.pr
        })
        if err then
          db.voucher.update(key, { used = false })
          print('failed to pay ("' .. err .. '") , marking voucher "' .. key .. '" as unused again')
          return { status = 'ERROR', reason = 'failed to pay' }
        end

        return {
          status = 'OK'
        }
      end
    end
  }
}

triggers = {
  payment_sent = function (payment)
    print("payment was successful, mark voucher " .. payment.extra.voucher .. " as success")
    db.voucher.update(payment.extra.voucher, { success = true })
  end
}
