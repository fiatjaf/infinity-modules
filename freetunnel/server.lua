title = 'Free Tunnel Server'

description = [[
  - Manages tunnel clients.
  - Starts the LNbits main tunnel service.

  This one is the free version, anyone can take a subdomain and keep it for free forever.
]]

models = {
  {
    name = 'client',
    display = 'Client',
    fields = {
      { name = 'subdomain', type = 'string', required = true }
    }
  }
}

actions = {
  create = {
    fields = {
      { name = 'subdomain', type = 'string', required = true }
    },
    handler = function (params)
      local key = db.client.add({ subdomain = params.subdomain })
      tunnel.add_client(params.subdomain, key)
      return key
    end
  }
}

triggers =  {
  init = function ()
    for _, item in ipairs(db.client.list()) do
      tunnel.add_client(item.value.subdomain, item.key)
    end
  end
}
