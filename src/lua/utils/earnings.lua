---Per-game money earnings tracker.
---
---Captures every dollar earned during a run, attributed to its source
---(joker / tag / interest / hands / discards / blind / playing-card).
---Stored on G.GAME.jackpotts_earnings for the gamestate serializer to expose.
---
---Hooks three sites:
---  1. add_round_eval_row — round-end income (jokers via calc_dollar_bonus,
---     tags, interest, hand/discard money, blind reward).
---  2. Card:get_p_dollars — per-played-card income (Lucky, Gold seal, Gold
---     enhancement) accumulated during scoring.
---  3. card_eval_status_text(card, 'dollars', amt) — mid-round joker
---     triggers (Faceless, Rough Gem, Trading Card, etc.). Filtered to
---     joker-set cards to avoid double-counting #2.

local earnings = {}

local function ensure_store()
    if not G or not G.GAME then return nil end
    if not G.GAME.jackpotts_earnings then
        G.GAME.jackpotts_earnings = { entries = {}, next_id = 1 }
    end
    return G.GAME.jackpotts_earnings
end

local function current_round_num()
    if G and G.GAME and G.GAME.round then return G.GAME.round end
    return 0
end

local function current_ante()
    if G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante then
        return G.GAME.round_resets.ante
    end
    return 0
end

local function record(entry)
    local store = ensure_store()
    if not store then return end
    entry.id = store.next_id
    entry.round = entry.round or current_round_num()
    entry.ante = entry.ante or current_ante()
    store.next_id = store.next_id + 1
    table.insert(store.entries, entry)
end

local function joker_key(card)
    if card and card.config and card.config.center and card.config.center.key then
        return card.config.center.key
    end
    return nil
end

local function tag_key(tag)
    if tag and tag.key then return tag.key end
    return nil
end

---Map add_round_eval_row's `name` field to a stable source category.
---Names like "joker1", "joker2", "tag1", "tag2" become "joker"/"tag";
---"hands"/"discards"/"interest"/"blind1" pass through trimmed.
local function classify_eval_row(name)
    if not name then return "unknown" end
    if name:match("^joker%d*$") then return "joker" end
    if name:match("^tag%d*$") then return "tag" end
    if name == "interest" then return "interest" end
    if name == "hands" then return "hands" end
    if name == "discards" then return "discards" end
    if name:match("^blind") then return "blind" end
    return name
end

function earnings.install()
    if earnings._installed then return end

    -- 1. add_round_eval_row — round-end income
    if type(add_round_eval_row) == "function" then
        local _orig = add_round_eval_row
        add_round_eval_row = function(args) ---@diagnostic disable-line: duplicate-set-field
            args = args or {}
            local dollars = args.dollars or 0
            if dollars ~= 0 and not args.saved then
                record({
                    source = classify_eval_row(args.name),
                    raw_name = args.name,
                    dollars = dollars,
                    joker_key = joker_key(args.card),
                    tag_key = tag_key(args.tag),
                    phase = "round_eval",
                })
            end
            return _orig(args)
        end
    end

    -- 2. Card:get_p_dollars — per-card scoring income (Lucky, Gold seal,
    --    Gold enhancement). Hook returns the dollar amount.
    if Card and Card.get_p_dollars then
        local _orig = Card.get_p_dollars
        Card.get_p_dollars = function(self) ---@diagnostic disable-line: duplicate-set-field
            local ret = _orig(self)
            if ret and ret ~= 0 then
                local enh = self.config and self.config.center and self.config.center.key
                local seal = self.seal
                local source = "card"
                if self.lucky_trigger then
                    source = "lucky"
                elseif seal == "Gold" then
                    source = "gold_seal"
                elseif enh == "m_gold" then
                    source = "gold_enhancement"
                end
                record({
                    source = source,
                    dollars = ret,
                    enhancement = enh,
                    seal = seal,
                    rank = self.base and self.base.value,
                    suit = self.base and self.base.suit,
                    phase = "scoring",
                })
            end
            return ret
        end
    end

    -- 3. card_eval_status_text with eval_type == 'dollars' on jokers —
    --    mid-round joker-triggered income (Faceless, Rough Gem, Trading
    --    Card, etc.). Filter to jokers to avoid double-counting #2.
    if type(card_eval_status_text) == "function" then
        local _orig = card_eval_status_text
        card_eval_status_text = function(card, eval_type, amt, percent, dir, extra) ---@diagnostic disable-line: duplicate-set-field
            if eval_type == "dollars" and amt and amt ~= 0
                and card and card.ability and card.ability.set == "Joker" then
                record({
                    source = "joker_trigger",
                    dollars = amt,
                    joker_key = joker_key(card),
                    phase = "play",
                })
            end
            return _orig(card, eval_type, amt, percent, dir, extra)
        end
    end

    earnings._installed = true
end

---Reset accumulator (called at game start). Safe to call when G.GAME absent.
function earnings.reset()
    if G and G.GAME then
        G.GAME.jackpotts_earnings = { entries = {}, next_id = 1 }
    end
end

return earnings
