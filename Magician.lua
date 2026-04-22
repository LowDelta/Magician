--- STEAMODDED HEADER
--- MOD_NAME: Magician
--- MOD_ID: Magician
--- MOD_AUTHOR: [dekta]
--- MOD_DESCRIPTION: Highly customazible luck mod
--- PREFIX: lkm
--- BADGE_COLOUR: f2c94c

----------------------------------------------
------------MOD CODE -------------------------

Magician = {}

-- Capture the mod and its config table at load time. `SMODS.current_mod` is only
-- valid while this file is being loaded; callbacks that fire later (tab clicks,
-- overlay buttons, hooks) must use these captured references instead.
Magician.mod    = SMODS and SMODS.current_mod or nil
Magician.config = (Magician.mod and Magician.mod.config) or {}

-- One-time migration from the old 0..3 intensity scale to the new 0..100 (%) scale.
-- Guarded by a stamp so legitimate low values (1, 2, 3 on the new scale) are never re-inflated.
if Magician.config.intensity_scale ~= "v2" then
    if type(Magician.config.intensity) == "number"
        and Magician.config.intensity > 0
        and Magician.config.intensity <= 3 then
        Magician.config.intensity = math.floor(Magician.config.intensity * (100 / 3) + 0.5)
    end
    Magician.config.intensity_scale = "v2"
end

-- Defaults for keys that may be missing from an older saved config.
local function default(key, value)
    if Magician.config[key] == nil then Magician.config[key] = value end
end
default("master_enabled",   true)
default("intensity",        50)
default("shrink",           100)
default("rarity_luck",      true)
default("edition_luck",     true)
default("allow_negative",   true)
default("seal_luck",        true)
default("tag_luck",         true)
default("voucher_luck",     true)
default("pack_luck",        true)
default("soul_luck",        true)
default("hits_luck",        true)
default("no_negative_hits", true)
default("bias_towards_run", true)

-- Legacy migration: old `lucky_card_luck` key -> new `hits_luck`.
if Magician.config.lucky_card_luck ~= nil then
    Magician.config.hits_luck        = Magician.config.lucky_card_luck
    Magician.config.lucky_card_luck  = nil
end

local function cfg()
    return Magician.config or {}
end

local function active(key)
    local c = cfg()
    return c.master_enabled and c[key]
end

-- Returns a 0..1 fraction. Config slider stores 0..100 (percent).
local function intensity()
    local c = cfg()
    local v = c.intensity or 50
    return math.max(0, math.min(1, v / 100))
end

-- Returns a 0..1 fraction. Controls how hard the pseudorandom wrapper collapses
-- a roll value (1.0 = full collapse -> guaranteed trigger at 100% intensity).
-- Multiplied by intensity() so both sliders must be up to reach full effect.
local function shrink_factor()
    local c = cfg()
    local s = c.shrink or 100
    return math.max(0, math.min(1, s / 100)) * intensity()
end

-- Safe pseudorandom wrapper
local function roll(key)
    if pseudorandom then return pseudorandom('lkm_' .. tostring(key)) end
    return math.random()
end

--------------------------------------------------
-- Deck-archetype analysis (used by `bias_towards_run`)
--   Each archetype has:
--     detect(g)  -> bool   inspects current run state and says "this fits"
--     recommend  -> {joker_key, ...}
--
-- Sources: Balatro community meta strategies (Baron / face decks, Flush stacks,
-- Hack-low-card chip scaling, Fibonacci chain, Odd-Todd / Even-Steven parity,
-- economy/high-card, Blueprint+Brainstorm copy core, edition/Perkeo stacking).
--------------------------------------------------
local function deck_cards()
    return (G and G.playing_cards) or {}
end

local function deck_rank_counts()
    local t = {}
    for _, c in ipairs(deck_cards()) do
        local v = c.base and c.base.value
        if v then t[v] = (t[v] or 0) + 1 end
    end
    return t
end

local function deck_suit_counts()
    local t = {}
    for _, c in ipairs(deck_cards()) do
        local s = c.base and c.base.suit
        if s then t[s] = (t[s] or 0) + 1 end
    end
    return t
end

local function deck_count_where(pred)
    local n = 0
    for _, c in ipairs(deck_cards()) do
        if pred(c) then n = n + 1 end
    end
    return n
end

local function most_played_hand(g)
    local best, best_name = -1, nil
    for name, data in pairs((g and g.hands) or {}) do
        local p = (type(data) == "table" and data.played) or 0
        if p > best then best, best_name = p, name end
    end
    return best_name
end

local function owned_jokers()
    local owned, showman = {}, false
    if G and G.jokers and G.jokers.cards then
        for _, c in ipairs(G.jokers.cards) do
            local k = c.config and c.config.center and c.config.center.key
            if k then
                owned[k] = true
                if k == "j_showman" then showman = true end
            end
        end
    end
    return owned, showman
end

Magician.archetypes = {
    {
        name = "King / Face Deck (Baron)",
        detect = function(g)
            local r = deck_rank_counts()
            local faces = (r["King"] or 0) + (r["Queen"] or 0) + (r["Jack"] or 0)
            return (r["King"] or 0) >= 8 or faces >= 16
        end,
        recommend = {
            "j_baron", "j_raised_fist", "j_mime", "j_sock_and_buskin",
            "j_stencil", "j_scholar", "j_photograph", "j_smiley",
            "j_stuntman", "j_scary_face", "j_reserved_parking",
        },
    },
    {
        name = "Low Card Chip Scaling (Hack)",
        detect = function(g)
            local r = deck_rank_counts()
            local low = (r["2"] or 0) + (r["3"] or 0) + (r["4"] or 0) + (r["5"] or 0)
            return low >= 14 or (r["5"] or 0) >= 6
        end,
        recommend = {
            "j_hack", "j_ride_the_bus", "j_green_joker", "j_runner",
            "j_walkie_talkie", "j_square_joker", "j_supernova",
        },
    },
    {
        name = "Fibonacci Chain",
        detect = function(g)
            local r = deck_rank_counts()
            local fib = (r["Ace"] or 0) + (r["2"] or 0) + (r["3"] or 0) + (r["5"] or 0) + (r["8"] or 0)
            return fib >= 16
        end,
        recommend = { "j_fibonacci", "j_scholar", "j_odd_todd", "j_walkie_talkie", "j_business" },
    },
    {
        name = "Flush / Suit Stack",
        detect = function(g)
            for _, v in pairs(deck_suit_counts()) do if v >= 18 then return true end end
            local h = most_played_hand(g)
            return h == "Flush" or h == "Flush House" or h == "Flush Five" or h == "Straight Flush"
        end,
        recommend = {
            "j_smeared", "j_four_fingers", "j_flower_pot", "j_droll", "j_sly", "j_wily",
            "j_greedy_joker", "j_lusty_joker", "j_wrathful_joker", "j_gluttonous_joker",
            "j_onyx_agate", "j_rough_gem", "j_arrowhead", "j_bloodstone",
        },
    },
    {
        name = "Straight Focus",
        detect = function(g)
            local h = most_played_hand(g)
            return h == "Straight" or h == "Straight Flush"
        end,
        recommend = { "j_four_fingers", "j_shortcut", "j_square_joker", "j_hack", "j_stuntman" },
    },
    {
        name = "Pair / Multi-of-a-Kind",
        detect = function(g)
            local h = most_played_hand(g)
            return h == "Pair" or h == "Two Pair" or h == "Three of a Kind"
                or h == "Four of a Kind" or h == "Full House" or h == "Flush House"
                or h == "Flush Five" or h == "Five of a Kind"
        end,
        recommend = {
            "j_stencil", "j_raised_fist", "j_wee", "j_duo", "j_trio",
            "j_family", "j_order", "j_tribe", "j_lucky_cat",
        },
    },
    {
        name = "Odd / Even Parity",
        detect = function(g)
            local r = deck_rank_counts()
            local odd  = (r["Ace"] or 0) + (r["3"] or 0) + (r["5"] or 0) + (r["7"] or 0) + (r["9"] or 0)
            local even = (r["2"] or 0) + (r["4"] or 0) + (r["6"] or 0) + (r["8"] or 0) + (r["10"] or 0)
            return odd >= 18 or even >= 18
        end,
        recommend = { "j_odd_todd", "j_even_steven", "j_scholar", "j_walkie_talkie", "j_business" },
    },
    {
        name = "Scaling Core (Blueprint copy)",
        detect = function(g)
            local owned = owned_jokers()
            local scaling = {
                "j_ride_the_bus", "j_green_joker", "j_constellation", "j_castle",
                "j_fortune_teller", "j_runner", "j_red_card", "j_obelisk",
                "j_hologram", "j_campfire", "j_ramen", "j_vampire", "j_madness",
            }
            for _, k in ipairs(scaling) do if owned[k] then return true end end
            return false
        end,
        recommend = { "j_blueprint", "j_brainstorm", "j_baseball", "j_hologram", "j_obelisk" },
    },
    {
        name = "Edition / Negative Stack",
        detect = function(g)
            local editioned = 0
            if G and G.jokers and G.jokers.cards then
                for _, c in ipairs(G.jokers.cards) do
                    local e = c.edition
                    if e and (e.foil or e.holo or e.polychrome or e.negative) then
                        editioned = editioned + 1
                    end
                end
            end
            return editioned >= 2
        end,
        recommend = { "j_perkeo", "j_hologram", "j_blueprint", "j_brainstorm", "j_showman" },
    },
    {
        name = "High Card / Economy",
        detect = function(g)
            return (g and g.dollars or 0) >= 25
                or most_played_hand(g) == "High Card"
        end,
        recommend = {
            "j_bull", "j_bootstraps", "j_credit_card", "j_delayed_grat",
            "j_golden", "j_rocket", "j_to_the_moon", "j_cloud_9", "j_seance",
            "j_vagabond", "j_egg",
        },
    },
    {
        name = "Stone Card / Marble",
        detect = function(g)
            -- Stone-enhanced playing cards carry `center.key == 'm_stone'` on the Card,
            -- not on its `base`. Their base.suit/value are still populated.
            local stones = deck_count_where(function(card)
                local center = card.config and card.config.center
                return center and center.key == "m_stone"
            end)
            local owned = owned_jokers()
            return stones >= 4 or owned["j_marble"] or owned["j_stone"]
        end,
        recommend = { "j_marble", "j_stone", "j_sparkle", "j_hiker", "j_castle" },
    },
}

-- Is a joker center a valid recommendation right now?
local function joker_available(key)
    if not key then return false end
    local center = G and G.P_CENTERS and G.P_CENTERS[key]
    if not center then return false end
    if center.unlocked == false then return false end
    local owned, showman = owned_jokers()
    if owned[key] and not showman then return false end
    return true
end

function Magician.get_recommended_joker()
    if not G or not G.GAME then return nil end
    local pool = {}
    local seen = {}
    for _, arch in ipairs(Magician.archetypes) do
        local ok, hit = pcall(arch.detect, G.GAME)
        if ok and hit then
            for _, k in ipairs(arch.recommend) do
                if joker_available(k) and not seen[k] then
                    seen[k]      = true
                    pool[#pool+1] = k
                end
            end
        end
    end
    if #pool == 0 then return nil end
    -- Use our seeded `roll` so two players on the same run seed get the same bias.
    local idx = 1 + math.floor(roll('bias_pick') * #pool)
    if idx < 1 then idx = 1 end
    if idx > #pool then idx = #pool end
    return pool[idx]
end

--------------------------------------------------
-- 1) Joker rarity bias (+ bias-towards-run + pack upgrade + soul boost)
--------------------------------------------------
local create_card_ref = create_card
function create_card(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)
    -- Bias towards current run: at 100% intensity, every shop joker becomes a
    -- synergy pick for the current deck / owned jokers / most-played hand.
    if active('bias_towards_run') and _type == 'Joker' and not forced_key and not legendary
        and G and G.shop_jokers and area == G.shop_jokers then
        if roll('bias_' .. tostring(key_append or '')) < intensity() then
            local pick = Magician.get_recommended_joker()
            if pick then
                forced_key = pick
                _rarity    = nil     -- forced_key bypasses rarity roll
            end
        end
    end

    -- Rarity bias: at 100% intensity every rolled joker is Rare.
    if active('rarity_luck') and _type == 'Joker' and not _rarity and not forced_key and not legendary then
        if roll('rar_' .. tostring(key_append or '')) < intensity() then
            _rarity = 0.99      -- Rare tier (> 0.95 threshold)
        end
    end

    local card = create_card_ref(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)

    -- Pack size upgrade: at 100% intensity every pack becomes Mega.
    if active('pack_luck') and _type == 'Booster' and not forced_key
        and card and card.config and card.config.center and card.config.center.key then
        local key = card.config.center.key
        local p   = intensity()
        if key:find('_normal_') and roll('pack1') < p then
            local jumbo_key = key:gsub('_normal_', '_jumbo_')
            if G.P_CENTERS and G.P_CENTERS[jumbo_key] then
                card:set_ability(G.P_CENTERS[jumbo_key], true, nil)
                key = jumbo_key
            end
        end
        if key:find('_jumbo_') and roll('pack2') < p then
            local mega_key = key:gsub('_jumbo_', '_mega_')
            if G.P_CENTERS and G.P_CENTERS[mega_key] then
                card:set_ability(G.P_CENTERS[mega_key], true, nil)
            end
        end
    end

    return card
end

--------------------------------------------------
-- 2) Edition luck
--------------------------------------------------
if poll_edition then
    local poll_edition_ref = poll_edition
    function poll_edition(_key, _mod, _no_neg, _guaranteed, _options)
        if active('edition_luck') then
            -- At 100% intensity, force a guaranteed edition on every poll.
            -- At partial intensity, roll to guarantee, else still heavily boost mod.
            if roll('ed_' .. tostring(_key or '')) < intensity() then
                _guaranteed = true
            else
                _mod = (_mod or 1) * (1 + 10 * intensity())
            end
            if cfg().allow_negative == false then _no_neg = true end
        end
        return poll_edition_ref(_key, _mod, _no_neg, _guaranteed, _options)
    end
end

--------------------------------------------------
-- 3) Seal luck
--------------------------------------------------
if poll_seal then
    local poll_seal_ref = poll_seal
    function poll_seal(args)
        if active('seal_luck') then
            args = args or {}
            -- 50x multiplier is enough to always produce a seal given vanilla base rates.
            args.mod = (args.mod or 1) * (1 + 49 * intensity())
            -- At max intensity, force a seal whether or not the caller originally set the flag.
            if intensity() >= 1.0 then
                args.guaranteed = true
            end
        end
        return poll_seal_ref(args)
    end
end

--------------------------------------------------
-- 4) Tag luck (reroll for rarer tag, using weight as proxy for rarity)
--------------------------------------------------
if get_next_tag_key then
    local get_next_tag_key_ref = get_next_tag_key
    function get_next_tag_key(append)
        local k1 = get_next_tag_key_ref(append)
        if active('tag_luck') and G.P_TAGS then
            -- Sample up to 15 extra rolls at 100% intensity and keep the rarest
            -- (rarer tag = lower `weight` in G.P_TAGS).
            local rerolls = math.floor(intensity() * 15 + 0.5)
            local best_k  = k1
            local best_w  = (G.P_TAGS[k1] and G.P_TAGS[k1].weight) or 1
            for i = 1, rerolls do
                local ki = get_next_tag_key_ref((append or '') .. '_lkm_' .. i)
                local wi = (G.P_TAGS[ki] and G.P_TAGS[ki].weight) or 1
                if wi < best_w then best_k, best_w = ki, wi end
            end
            return best_k
        end
        return k1
    end
end

--------------------------------------------------
-- 5) Voucher luck (extra reroll chance)
--------------------------------------------------
if get_next_voucher_key then
    local get_next_voucher_key_ref = get_next_voucher_key
    function get_next_voucher_key(_from_tag)
        local k = get_next_voucher_key_ref(_from_tag)
        if active('voucher_luck') then
            -- At 100% intensity, always reroll once for a fresh pick.
            if roll('voucher') < intensity() then
                return get_next_voucher_key_ref(_from_tag)
            end
        end
        return k
    end
end

--------------------------------------------------
-- 6) Hits Luck
--    Every probabilistic trigger in Balatro is a `pseudorandom('seed') < threshold`
--    comparison. We intercept known POSITIVE hit seeds and pull the result toward 0
--    so the trigger fires more often.
--
--    When `no_negative_hits` is on, negative-outcome seeds (joker dies, card breaks)
--    are pushed the OPPOSITE way so the bad thing happens less often.
--    When `no_negative_hits` is off, negative seeds are left at vanilla.
--
--    All other seeds (card draw, world gen, etc.) are untouched, so base-game
--    determinism outside of hit triggers is preserved.
--------------------------------------------------
local POSITIVE_HIT_SEEDS = {
    -- Lucky Card enhancement
    lucky_mult       = true,    -- 1/5  +20 mult
    lucky_money      = true,    -- 1/15 +$20
    -- Jokers
    ["8ball"]        = true,    -- 8 Ball: 1/4 Tarot on played 8
    space            = true,    -- Space Joker: 1/4 level up
    business         = true,    -- Business Card: 1/2 $2 on face card
    reserved_parking = true,    -- Reserved Parking: 1/2 $1 on face in hand
    bloodstone       = true,    -- Bloodstone: 1/2 x1.5 mult on Heart
    sixth_sense      = true,    -- Sixth Sense: first-6-of-round -> Spectral
    seance           = true,    -- Séance: 1/10 Spectral on Straight Flush
    hit_the_road     = true,    -- Hit the Road: 1/5 on Jack discard
    halu             = true,    -- Hallucination tarot on pack skip
    wheel_of_fortune = true,    -- Wheel of Fortune: 1/4 edition onto a joker
}

local NEGATIVE_HIT_SEEDS = {
    gros_michel           = true,  -- 1/6 chance to die end of round
    cavendish             = true,  -- 1/1000 chance to die end of round
    gros_michel_extinct   = true,
    cavendish_extinct     = true,
    glass                 = true,  -- Glass Card: 1/4 break after scoring -- destructive, guard it
}

local pseudorandom_ref = pseudorandom
function pseudorandom(seed, min, max)
    local v = pseudorandom_ref(seed, min, max)

    -- Only intervene on simple `pseudorandom(seed)` calls. If `min`/`max` were passed
    -- the result lives in a different range and scaling it is unsafe.
    if type(seed) ~= "string" or min or max then
        return v
    end

    local shrink = shrink_factor()  -- 1.0 at max -> collapses the roll to 0 or 1

    -- Soul / Black Hole: vanilla rolls `pseudorandom('soul_Tarot1')` etc.
    if active('soul_luck') and seed:sub(1, 5) == "soul_" then
        v = v * (1 - shrink)                     -- at 100%, always triggers
        return v
    end

    if active('hits_luck') then
        if POSITIVE_HIT_SEEDS[seed] then
            -- Pull toward 0 -> `v < threshold` succeeds more often.
            v = v * (1 - shrink)                 -- at 100%, v = 0 -> always succeeds
        elseif NEGATIVE_HIT_SEEDS[seed] and cfg().no_negative_hits then
            -- Push toward 1 -> `v < threshold` fails more often.
            v = v + (1 - v) * shrink             -- at 100%, v = 1 -> never triggers
        end
    end

    return v
end

--------------------------------------------------
-- Config UI builder (used by main-menu Mods tab + in-game overlay)
--------------------------------------------------
function Magician.build_config_nodes(standalone)
    local c = Magician.config

    -- One toggle cell (goes inside a column of a multi-column row)
    local function toggle_cell(label, key)
        return {
            n = G.UIT.C, config = {align = "cl", padding = 0.05, minw = 5.2},
            nodes = {
                create_toggle({
                    label     = label,
                    ref_table = c,
                    ref_value = key,
                    w         = 5, h = 0.5,
                }),
            },
        }
    end

    -- Lay out toggles in horizontal rows of `per_row` cells.
    local function toggle_grid(entries, per_row)
        per_row = per_row or 2
        local rows = {}
        for i = 1, #entries, per_row do
            local cols = {}
            for j = 0, per_row - 1 do
                local e = entries[i + j]
                if e then cols[#cols + 1] = toggle_cell(e[1], e[2]) end
            end
            rows[#rows + 1] = {
                n = G.UIT.R, config = {align = "cm", padding = 0.02},
                nodes = cols,
            }
        end
        return rows
    end

    local function slider_cell(label, key, min, max, w)
        return {
            n = G.UIT.C, config = {align = "cm", padding = 0.05, minw = (w or 4.5) + 0.3},
            nodes = {
                create_slider({
                    label     = label,
                    ref_table = c,
                    ref_value = key,
                    w         = w or 4.5, h = 0.4,
                    min       = min, max = max,
                    decimal_places = 0,
                }),
            },
        }
    end

    -- Two sliders side-by-side on one row.
    local function slider_pair(left, right)
        return {
            n = G.UIT.R, config = {align = "cm", padding = 0.04},
            nodes = { left, right },
        }
    end

    -- Top bar: title on the left, Master Enabled toggle on the right.
    local top_bar = {
        n = G.UIT.R, config = {align = "cm", padding = 0.08},
        nodes = {
            { n = G.UIT.C, config = {align = "cl", padding = 0.1, minw = 5}, nodes = {
                { n = G.UIT.T, config = {text = "Luck Mod Settings", scale = 0.55, colour = G.C.UI.TEXT_LIGHT}},
            }},
            { n = G.UIT.C, config = {align = "cr", padding = 0.1, minw = 5}, nodes = {
                create_toggle({
                    label     = "Master Enabled",
                    ref_table = c,
                    ref_value = "master_enabled",
                    w         = 5, h = 0.5,
                }),
            }},
        },
    }

    local toggles = toggle_grid({
        {"Biased Towards Run",     "bias_towards_run"},
        {"Joker Rarity Luck",      "rarity_luck"},
        {"Edition Luck",           "edition_luck"},
        {"  Allow Negative Edition", "allow_negative"},
        {"Seal Luck",              "seal_luck"},
        {"Tag Luck",               "tag_luck"},
        {"Voucher Luck",           "voucher_luck"},
        {"Pack Size Luck",         "pack_luck"},
        {"Soul / Black Hole Luck", "soul_luck"},
        {"Hits Luck",              "hits_luck"},
        {"  No Negative Hits",     "no_negative_hits"},
    }, 2)

    local nodes = {
        top_bar,
        slider_pair(
            slider_cell("Intensity (%)", "intensity", 0, 100),
            slider_cell("Shrink (%)",    "shrink",    0, 100)
        ),
        { n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            { n = G.UIT.T, config = {text = "-- Toggles --", scale = 0.35, colour = G.C.UI.TEXT_LIGHT}},
        }},
    }
    for _, r in ipairs(toggles) do nodes[#nodes + 1] = r end

    if standalone then
        nodes[#nodes + 1] = {
            n = G.UIT.R, config = {align = "cm", padding = 0.15, minh = 0.7},
            nodes = {
                UIBox_button({
                    label  = {"Back"},
                    button = "lkm_exit_overlay",
                    minw   = 4, minh = 0.6, scale = 0.45,
                    colour = G.C.RED,
                }),
            },
        }
    end

    return {
        n = G.UIT.ROOT,
        config = {r = 0.1, minw = 11, align = "tm", padding = 0.15, colour = G.C.BLACK},
        nodes = nodes,
    }
end

-- Steamodded Mods-menu tab entry
SMODS.current_mod.config_tab = function()
    return Magician.build_config_nodes(false)
end

--------------------------------------------------
-- In-game entry points
--------------------------------------------------
-- Overlay opener: called from any button we register.
-- Sets `Magician.overlay_open` while our overlay is showing so F6 can distinguish
-- our overlay from any other (shop, pack, settings, etc.) and only auto-close ours.
Magician.overlay_open = false

G.FUNCS.lkm_open_config = function(e)
    if not Magician.config then return end
    Magician.overlay_open = true
    G.FUNCS.overlay_menu({
        definition = create_UIBox_generic_options({
            contents = { Magician.build_config_nodes(true) },
            back_func = "lkm_exit_overlay",
        }),
    })
end

-- Dedicated exit func so we can clear the open flag when the user backs out.
G.FUNCS.lkm_exit_overlay = function(e)
    Magician.overlay_open = false
    G.FUNCS.exit_overlay_menu(e)
end

-- Inject a "Luck Mod" button into the in-game pause menu (Esc during a run).
-- We walk the returned UIBox tree defensively and append a new row.
local function append_button_to_pause(ui)
    if type(ui) ~= "table" then return ui end

    local button_row = {
        n = G.UIT.R, config = {align = "cm", padding = 0.08, minh = 0.1},
        nodes = {
            UIBox_button({
                label   = {"Luck Mod"},
                button  = "lkm_open_config",
                minw    = 3.85, minh = 0.6, scale = 0.45,
                colour  = HEX and HEX("f2c94c") or G.C.ORANGE,
            }),
        },
    }

    -- Locate first column with multiple row children (the main button column of the pause menu)
    -- and append our button row at the bottom.
    local function walk(node)
        if type(node) ~= "table" then return false end
        if node.nodes and type(node.nodes) == "table" then
            if node.n == G.UIT.C then
                local row_count = 0
                for _, child in ipairs(node.nodes) do
                    if type(child) == "table" and child.n == G.UIT.R then
                        row_count = row_count + 1
                    end
                end
                if row_count >= 2 then
                    table.insert(node.nodes, button_row)
                    return true
                end
            end
            for _, child in ipairs(node.nodes) do
                if walk(child) then return true end
            end
        end
        return false
    end

    pcall(walk, ui)
    return ui
end

-- Hook the pause menu (Esc during a run) to add a shortcut button.
if rawget(_G, "create_UIBox_pause_options") then
    local ref = create_UIBox_pause_options
    function create_UIBox_pause_options(...)
        return append_button_to_pause(ref(...))
    end
end

--------------------------------------------------
-- Inject a "Luck Mod" TAB into the Settings menu (alongside Game / Video / Graphics / Audio).
-- Strategy: temporarily wrap `create_tabs` while `create_UIBox_settings` is running,
-- and append our tab to the args.tabs list before it builds the UI.
--------------------------------------------------
if rawget(_G, "create_UIBox_settings") and rawget(_G, "create_tabs") then
    local settings_ref = create_UIBox_settings
    local tabs_ref     = create_tabs
    local injecting    = false

    local function luck_tab()
        return {
            label                   = "Luck Mod",
            chosen                  = false,
            tab_definition_function = function()
                return Magician.build_config_nodes(false)
            end,
        }
    end

    function create_tabs(args)
        if injecting and args and type(args.tabs) == "table" then
            local already = false
            for _, t in ipairs(args.tabs) do
                if t and t.label == "Luck Mod" then already = true break end
            end
            if not already then
                args.tabs[#args.tabs + 1] = luck_tab()
            end
        end
        return tabs_ref(args)
    end

    function create_UIBox_settings(tab)
        injecting = true
        local ok, ui = pcall(settings_ref, tab)
        injecting = false
        if not ok then error(ui) end
        return ui
    end
end

--------------------------------------------------
-- F6 keybind: open the config overlay from anywhere (main menu, run, shop, etc.)
--------------------------------------------------
if love and love.keypressed then
    local love_keypressed_ref = love.keypressed
    function love.keypressed(key, ...)
        if key == "f6" and G and G.FUNCS and G.FUNCS.lkm_open_config then
            if not G.OVERLAY_MENU then
                -- No overlay shown -> open ours.
                G.FUNCS.lkm_open_config()
                return
            elseif Magician.overlay_open then
                -- Our overlay is already open -> toggle it closed.
                G.FUNCS.lkm_exit_overlay()
                return
            end
            -- Some other overlay is open (shop, pack, settings, etc.): do nothing
            -- and let the keypress fall through to vanilla handling.
        end
        return love_keypressed_ref(key, ...)
    end
end
