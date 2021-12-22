title = 'LNURLPoS'

description = "The magic-based completely offline point-of-sale."

models = {
  {
    name = 'definition',
    display = 'Definitions',
    fields = {
      { name = 'key', display = 'Encryption Key', type = 'string' },
      {
        name = 'currency',
        display = 'Currency',
        type = 'select',
        options = utils.currencies
      },
      {
        name = 'description',
        display = 'Invoice Description',
        type = 'string',
        default = 'LNURLPoS Payment'
      },
      {
        name = 'success_message',
        display = 'Message to display along with the confirmation code',
        type = 'string',
        default = 'Confirmation Code'
      },
    },
    single = true,
  }
}

actions = {
  lnurlp = {
    fields = {
      { name = "p", display = "encrypted payload", type = "string", required = true },
      { name = "lnurl", display = "amount (in msat)", type = "string" },
    },
    handler = function (params)
      local defs = db.definition.get()
      if not defs or not defs.key or not defs.currency then
        return {
          status = 'ERROR',
          reason = 'LNURLPoS setup not finished or unknown LNURLPoS.'
        }
      end

      local pin, amt, err = utils.snigirev_decrypt(defs.key, params.p)
      if err then
        return {
          status = 'ERROR',
          reason = 'Failed to decrypt payload: ' .. err
        }
      end

      if defs.currency == 'sat' then
        amt = amt * 1000
      end
      local msat_amount = math.ceil(
        (amt / 100) * utils.get_msats_per_fiat_unit(defs.currency)
      )

      local metadata = json.encode({
        {'text/plain', defs.description}
      })

      if params.amount then
        -- second call, return invoice
        local invoice, err = wallet.create_invoice({
          description_hash = utils.sha256(metadata),
          msatoshi = msat_amount,
        })

        if err then
          return {
            status = 'ERROR',
            reason = err
          }
        end

        local strpin = tostring(math.floor(pin))
        local ct, iv, err = lnurl.successaction_aes(invoice.preimage, strpin)
        if err then
          return {
            status = 'ERROR',
            reason = 'Failed to encrypt confirmation code: ' .. err
          }
        end

        return {
          routes = emptyarray(),
          pr = invoice.bolt11,
          successAction = {
            tag = 'aes',
            description = defs.success_message,
            ciphertext = ct,
            iv = iv,
          }
        }
      else
        -- first call, return params
        return {
          tag = 'payRequest',
          minSendable = msat_amount,
          maxSendable = msat_amount,
          metadata = metadata,
          callback = params._url,
        }
      end
    end
  },
  get_debug_lnurl = {
    fields = {
      { name = "pin", type = "number", required = true },
      { name = "amount", type = "number", required = true },
    },
    handler = function (params)
      local defs = db.definition.get()
      if not defs or not defs.key or not defs.currency then
        return {
          status = 'ERROR',
          reason = 'LNURLPoS setup not finished or unknown LNURLPoS.'
        }
      end

      local base_url = params._url:gsub("/action/.*", '/action/lnurlp')
      local blob = utils.snigirev_encrypt(defs.key, params.pin, params.amount)
      return lnurl.bech32_encode(base_url .. "?p=" .. blob)
    end,
  }
}
