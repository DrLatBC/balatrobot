-- src/lua/endpoints/cash_out.lua

-- ==========================================================================
-- CashOut Endpoint Params
-- ==========================================================================

---@class Request.Endpoint.CashOut.Params

-- ==========================================================================
-- CashOut Endpoint
-- ==========================================================================

---@type Endpoint
return {

  name = "cash_out",

  description = "Cash out and collect round rewards",

  schema = {},

  requires_state = { G.STATES.ROUND_EVAL },

  ---@param _ Request.Endpoint.CashOut.Params
  ---@param send_response fun(response: Response.Endpoint)
  execute = function(_, send_response)
    sendDebugMessage("Init cash_out()", "BB.ENDPOINTS")

    local num_items = function(area)
      local count = 0
      if area and area.cards then
        for _, v in ipairs(area.cards) do
          if v.children.buy_button and v.children.buy_button.definition then
            count = count + 1
          end
        end
      end
      return count
    end

    -- Helper: check if the cash_out_button UI exists, meaning all scoring
    -- rows from add_round_eval_row have finished (it's created last).
    local function scoring_complete()
      if not G.round_eval then return false end
      for _, b in ipairs(G.I.UIBOX) do
        if b:get_UIE_by_ID("cash_out_button") then return true end
      end
      return false
    end

    -- Wait for scoring events to finish before triggering cash out.
    -- When the bot's play() times out (e.g. win overlay pause) and the
    -- Python side re-polls then sends cash_out, scoring-row events from
    -- add_round_eval_row may still be in-flight.  Calling G.FUNCS.cash_out
    -- immediately nils G.round_eval and crashes at common_events.lua:1148.
    G.E_MANAGER:add_event(Event({
      trigger = "condition",
      blocking = false,
      func = function()
        if not scoring_complete() then return false end

        sendDebugMessage("cash_out() - scoring complete, triggering cash out", "BB.ENDPOINTS")
        G.FUNCS.cash_out({ config = {} })

        -- Wait for SHOP state after the cash-out transition completes
        G.E_MANAGER:add_event(Event({
          trigger = "condition",
          blocking = false,
          func = function()
            local done = false
            if G.STATE == G.STATES.SHOP and G.STATE_COMPLETE then
              done = num_items(G.shop_booster) > 0 or num_items(G.shop_jokers) > 0 or num_items(G.shop_vouchers) > 0
              if done then
                sendDebugMessage("Return cash_out() - reached SHOP state", "BB.ENDPOINTS")
                send_response(BB_GAMESTATE.get_gamestate())
                return done
              end
            end
            return done
          end,
        }))
        return true
      end,
    }))
  end,
}
