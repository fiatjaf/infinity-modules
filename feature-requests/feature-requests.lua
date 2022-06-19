title = 'Feature Requests'

description = [[This module allows any project owner to create a page users can request new features from.

With each request users must attach some satoshis. To upvote requests, users also attach satoshis (each counts as one vote).

Project owners are free to cancel features and keep the money.
[URL]($extBase/)
]]

models = {
    {
        name = 'request',
        display = 'Feature Requests',
        fields = {
            { name = 'title', display = 'Request Title', required = true, type = 'string' },
            { name = 'description', display = 'Description', type = 'string' },
            { name = 'sats', display = 'Satoshi for request', type = 'msatoshi', default = 0 },
            { name = 'paid', display = 'Has the request been paid', type = 'boolean', default = false }
        },
        default_sort = 'sats desc'
    }
}

actions = {
    get_metadata = {
        handler = function()
            return {
                title = title
            }
        end
    },

    -- Filters all feature requests and returns only paid
    get_paid_requests = {
        handler = function()
            local arr = db.request.list()
            local new_index = 1

            local size_orig = #arr
            for _, v in ipairs(arr) do
                if v.value.paid then
                    v.value.sats = v.value.sats / 1000
                    arr[new_index] = v
                    new_index = new_index + 1
                end
            end
            for i = new_index, size_orig do arr[i] = nil end

            return arr
        end
    },

    -- Generate invoice for feature request creation
    generate_creation_invoice = {
        fields = {
            -- Params for request creation
            { name = 'title', display = 'Request Title', required = true, type = 'string' },
            { name = 'description', display = 'Description', type = 'string' },
            { name = 'sats', display = 'Satoshi for request', type = 'msatoshi', required = true },
            -- Session is unique identificator for user, it's used to notify specific user on front
            { name = 'session', required = true, type = 'string' }
        },
        handler = function(params)
            local request_key = db.request.add({
                title = params.title,
                description = params.description,
                sats = params.sats * 1000
            })
            print("generate_creation_invoice", params, request_key)

            local invoice = wallet.create_invoice({
                description = "Create feature request with title " .. params.title,
                msatoshi = params.sats * 1000,
                extra = {
                    type = 'create',
                    request_key = request_key,
                    session = params.session
                },
            })

            return invoice.bolt11

        end
    },

    -- Generate invoice for upvote
    generate_upvote_invoice = {
        fields = {
            { name = 'request', required = true, type = 'ref', ref = 'request', as = 'title' },
            { name = 'amount', required = true, type = 'msatoshi' },
            -- Session is unique identificator for user, it's used to notify specific user on front
            { name = 'session', required = true, type = 'string' }
        },
        handler = function(params)
            print("generate_upvote_invoice params", params)
            local request = db.request.get(params.request)
            print("generate_upvote_invoice request", request)

            local invoice = wallet.create_invoice({
                description = "Upvote to " .. request.title,
                msatoshi = params.amount * 1000,
                extra = {
                    type = 'upvote',
                    request_key = params.request,
                    session = params.session
                },
            })

            return invoice.bolt11

        end
    }
}

triggers = {
    payment_received = function(payment)
        print("payment_received", payment, "app_id", app.id)

        if payment.tag ~= app.id and not payment.extra.type then
            return
        end

        if payment.extra.type == 'upvote' then
            local request = db.request.get(payment.extra.request_key)

            -- Increment request sats amount
            db.request.update(payment.extra.request_key, { sats = request.sats + payment.amount })

            -- Notify user on frontend
            app.emit_event('request-upvoted', payment.extra.session)
        end

        if payment.extra.type == 'create' then
            db.request.update(payment.extra.request_key, { paid = true })

            -- Notify user on frontend
            app.emit_event('request-created', payment.extra.session)
        end
    end
}
