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
      { name = "nce", type = "string", required = true },
      { name = "pld", type = "string", required = true },
      { name = "amount", type = "string" },
    },
    handler = function (params)
      local defs = db.definition.get()
      if not defs or not defs.key or not defs.currency then
        return {
          status = 'ERROR',
          reason = 'LNURLPoS setup not finished or unknown LNURLPoS.'
        }
      end

      local pin, amt, err = utils.snigirev_decrypt(defs.key, params.nce, params.pld)
      if err then
        return {
          status = 'ERROR',
          reason = 'Failed to decrypt payload: ' .. err
        }
      end

      local msat_amount
      if defs.currency == 'sat' then
        msat_amount = amt * 1000
      else
        msat_amount = utils.get_msats_per_fiat_unit(amt / 100)
      end

      local metadata = json.encode({
        {'text/plain', defs.description}
      })

      if params.amount then
        -- second call, return invoice
        local invoice = wallet.create_invoice({
          description_hash = utils.sha256(metadata),
          msatoshi = msat_amount,
        })

        local strpin = tostring(math.floor(pin))
        local ct, iv = lnurl.successaction_aes(invoice.preimage, strpin)
        return {
          routes = {''},
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
      local nonce, payload = utils.snigirev_encrypt(defs.key, params.pin, params.amount)
      return lnurl.bech32_encode(base_url .. "?nce=" .. nonce .. "&pld=" .. payload)
    end,
  }
}
