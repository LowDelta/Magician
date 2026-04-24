--- STEAMODDED HEADER
--- MOD_NAME: Magician
--- MOD_ID: Magician
--- MOD_AUTHOR: [dekta]
--- MOD_DESCRIPTION: Customizable luck manipulation
--- PREFIX: lkm
--- BADGE_COLOUR: f2c94c

Magician = {}

Magician.mod    = SMODS and SMODS.current_mod or nil
Magician.config = (Magician.mod and Magician.mod.config) or {}

if Magician.config.intensity_scale ~= "v2" then
    if type(Magician.config.intensity) == "number"
        and Magician.config.intensity > 0
        and Magician.config.intensity <= 3 then
        Magician.config.intensity = math.floor(Magician.config.intensity * (100 / 3) + 0.5)
    end
    Magician.config.intensity_scale = "v2"
end

-- Rename migration must run BEFORE defaults, otherwise defaults populate
-- hits_luck=true and the nil-check below always skips the copy.
if Magician.config.lucky_card_luck ~= nil then
    if Magician.config.hits_luck == nil then
        Magician.config.hits_luck = Magician.config.lucky_card_luck
    end
    Magician.config.lucky_card_luck = nil
end

local function default(key, value)
    if Magician.config[key] == nil then Magician.config[key] = value end
end
default("master_enabled",   true)
default("intensity",        50)
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

local function cfg()
    return Magician.config or {}
end

function Magician.save_config()
    if SMODS and SMODS.save_mod_config and Magician.mod then
        pcall(SMODS.save_mod_config, Magician.mod)
    end
end

local function active(key)
    local c = cfg()
    return c.master_enabled and c[key]
end

local function intensity()
    local c = cfg()
    local v = c.intensity or 50
    return math.max(0, math.min(1, v / 100))
end

local function roll(key)
    if pseudorandom then return pseudorandom('lkm_' .. tostring(key)) end
    return math.random()
end

local function deck_cards()
    return (G and G.playing_cards) or {}
end

-- Per-recommendation cache. Archetype detect() callbacks and joker_available()
-- hammer these functions; caching collapses them to one iteration per
-- get_recommended_joker() call. The cache is cleared at the start of each
-- recommendation; no external code depends on these functions outside that path.
local _deck_cache = {}

local function deck_cache_reset()
    _deck_cache = {}
end

local function deck_rank_counts()
    if _deck_cache.ranks then return _deck_cache.ranks end
    local t = {}
    for _, c in ipairs(deck_cards()) do
        local v = c.base and c.base.value
        if v then t[v] = (t[v] or 0) + 1 end
    end
    _deck_cache.ranks = t
    return t
end

local function deck_suit_counts()
    if _deck_cache.suits then return _deck_cache.suits end
    local t = {}
    for _, c in ipairs(deck_cards()) do
        local s = c.base and c.base.suit
        if s then t[s] = (t[s] or 0) + 1 end
    end
    _deck_cache.suits = t
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
    if _deck_cache.owned then
        return _deck_cache.owned, _deck_cache.showman
    end
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
    _deck_cache.owned = owned
    _deck_cache.showman = showman
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
    deck_cache_reset()
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
    local idx = 1 + math.floor(roll('bias_pick') * #pool)
    if idx < 1 then idx = 1 end
    if idx > #pool then idx = #pool end
    return pool[idx]
end

local create_card_ref = create_card
function create_card(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)
    if active('bias_towards_run') and _type == 'Joker' and not forced_key and not legendary
        and G and G.shop_jokers and area == G.shop_jokers then
        if roll('bias_' .. tostring(key_append or '')) < intensity() then
            local pick = Magician.get_recommended_joker()
            if pick then
                forced_key = pick
                _rarity    = nil
            end
        end
    end

    if active('rarity_luck') and _type == 'Joker' and not _rarity and not forced_key and not legendary then
        if roll('rar_' .. tostring(key_append or '')) < intensity() then
            _rarity = 0.99
        end
    end

    local card = create_card_ref(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append)

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

if poll_edition then
    local poll_edition_ref = poll_edition
    function poll_edition(_key, _mod, _no_neg, _guaranteed, _options)
        if active('edition_luck') then
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

if poll_seal then
    local poll_seal_ref = poll_seal
    function poll_seal(args)
        if active('seal_luck') then
            args = args or {}
            args.mod = (args.mod or 1) * (1 + 49 * intensity())
            if intensity() >= 1.0 then
                args.guaranteed = true
            end
        end
        return poll_seal_ref(args)
    end
end

if get_next_tag_key then
    local get_next_tag_key_ref = get_next_tag_key
    function get_next_tag_key(append)
        local k1 = get_next_tag_key_ref(append)
        if active('tag_luck') and G.P_TAGS then
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

if get_next_voucher_key then
    local get_next_voucher_key_ref = get_next_voucher_key
    function get_next_voucher_key(_from_tag)
        local k = get_next_voucher_key_ref(_from_tag)
        if active('voucher_luck') then
            if roll('voucher') < intensity() then
                return get_next_voucher_key_ref(_from_tag)
            end
        end
        return k
    end
end

local POSITIVE_HIT_SEEDS = {
    lucky_mult       = true,
    lucky_money      = true,
    ["8ball"]        = true,
    space            = true,
    business         = true,
    reserved_parking = true,
    bloodstone       = true,
    sixth_sense      = true,
    seance           = true,
    hit_the_road     = true,
    halu             = true,
    wheel_of_fortune = true,
}

local NEGATIVE_HIT_SEEDS = {
    gros_michel           = true,
    cavendish             = true,
    gros_michel_extinct   = true,
    cavendish_extinct     = true,
    glass                 = true,
}

local pseudorandom_ref = pseudorandom
function pseudorandom(seed, min, max)
    local v = pseudorandom_ref(seed, min, max)

    -- pseudorandom is extremely hot. Bail before touching config whenever this
    -- call cannot possibly match any of our seed tables.
    if type(seed) ~= "string" or min or max then
        return v
    end
    local positive = POSITIVE_HIT_SEEDS[seed]
    local negative = NEGATIVE_HIT_SEEDS[seed]
    local is_soul  = seed:sub(1, 5) == "soul_"
    if not (is_soul or positive or negative) then
        return v
    end

    local c = Magician.config or {}
    if not c.master_enabled then return v end

    local iv = c.intensity or 50
    local p  = math.max(0, math.min(1, iv / 100))

    if is_soul and c.soul_luck then
        return v * (1 - p)
    end

    if c.hits_luck then
        if positive then
            return v * (1 - p)
        elseif negative and c.no_negative_hits then
            return v + (1 - v) * p
        end
    end

    return v
end

function Magician.build_config_nodes(standalone)
    local c = Magician.config

    -- create_toggle(w=4.7) has natural inner width 4.7 + 0.3*4.7 + 0.2 padding = 6.31.
    -- Using this as the outer cell's minw forces both populated and empty cells to
    -- render at the same width so every row lines up under ROOT align="tm".
    local CELL_MINW = 6.31

    local function toggle_cell(label, key)
        return {
            n = G.UIT.C, config = {align = "cl", padding = 0.03, minw = CELL_MINW},
            nodes = {
                create_toggle({
                    label     = label,
                    ref_table = c,
                    ref_value = key,
                    w         = 4.7, h = 0.4,
                    callback  = Magician.save_config,
                }),
            },
        }
    end

    local function empty_cell()
        return {
            n = G.UIT.C, config = {align = "cl", padding = 0.03, minw = CELL_MINW},
            nodes = {
                { n = G.UIT.B, config = {w = CELL_MINW, h = 0.4} },
            },
        }
    end

    local function toggle_row(entries)
        local cols = {}
        for _, e in ipairs(entries) do
            cols[#cols + 1] = toggle_cell(e[1], e[2])
        end
        while #cols < 2 do
            cols[#cols + 1] = empty_cell()
        end
        return {
            n = G.UIT.R, config = {align = "cm", padding = 0.01},
            nodes = cols,
        }
    end

    local top_bar = {
        n = G.UIT.R, config = {align = "cm", padding = 0.04},
        nodes = {
            { n = G.UIT.C, config = {align = "cl", padding = 0.03, minw = CELL_MINW}, nodes = {
                { n = G.UIT.T, config = {text = "Magician", scale = 0.5, colour = G.C.UI.TEXT_LIGHT}},
            }},
            { n = G.UIT.C, config = {align = "cr", padding = 0.03, minw = CELL_MINW}, nodes = {
                create_toggle({
                    label     = "Enabled",
                    ref_table = c,
                    ref_value = "master_enabled",
                    w         = 4.7, h = 0.4,
                    callback  = Magician.save_config,
                }),
            }},
        },
    }

    local nodes = {
        top_bar,
        {
            n = G.UIT.R, config = {align = "cm", padding = 0.01},
            nodes = {
                create_slider({
                    label     = "Intensity (%)",
                    ref_table = c,
                    ref_value = "intensity",
                    w         = 4.7, h = 0.35,
                    min       = 0, max = 100,
                    decimal_places = 0,
                }),
            },
        },
        toggle_row({{"Bias to Run", "bias_towards_run"}, {"Rarity Luck", "rarity_luck"}}),
        toggle_row({{"Edition Luck", "edition_luck"}, {"Allow Negative Ed.", "allow_negative"}}),
        toggle_row({{"Seal Luck", "seal_luck"}, {"Tag Luck", "tag_luck"}}),
        toggle_row({{"Voucher Luck", "voucher_luck"}, {"Pack Size Luck", "pack_luck"}}),
        toggle_row({{"Soul / BH Luck", "soul_luck"}, {"Hits Luck", "hits_luck"}}),
        toggle_row({{"No Neg. Luck Hits", "no_negative_hits"}}),
    }

    if standalone then
        nodes[#nodes + 1] = {
            n = G.UIT.R, config = {align = "cm", padding = 0.08, minh = 0.5},
            nodes = {
                UIBox_button({
                    label  = {"Back"},
                    button = "lkm_exit_overlay",
                    minw   = 3.5, minh = 0.5, scale = 0.4,
                    colour = G.C.RED,
                }),
            },
        }
    end

    return {
        n = G.UIT.ROOT,
        config = {r = 0.1, minw = 10.5, align = "tm", padding = 0.08, colour = {0, 0, 0, 0.25}},
        nodes = nodes,
    }
end

SMODS.current_mod.config_tab = function()
    return Magician.build_config_nodes(false)
end

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

G.FUNCS.lkm_exit_overlay = function(e)
    Magician.overlay_open = false
    Magician.save_config()
    G.FUNCS.exit_overlay_menu(e)
end

local function append_button_to_pause(ui)
    if type(ui) ~= "table" then return ui end

    local button_row = {
        n = G.UIT.R, config = {align = "cm", padding = 0.08, minh = 0.1},
        nodes = {
            UIBox_button({
                label   = {"Magician"},
                button  = "lkm_open_config",
                minw    = 3.85, minh = 0.6, scale = 0.45,
                colour  = HEX and HEX("f2c94c") or G.C.ORANGE,
            }),
        },
    }

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

if rawget(_G, "create_UIBox_pause_options") then
    local ref = create_UIBox_pause_options
    function create_UIBox_pause_options(...)
        return append_button_to_pause(ref(...))
    end
end

if rawget(_G, "create_UIBox_settings") and rawget(_G, "create_tabs") then
    local settings_ref = create_UIBox_settings
    local tabs_ref     = create_tabs
    local injecting    = false

    local function luck_tab()
        return {
            label                   = "Magician",
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
                if t and t.label == "Magician" then already = true break end
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

if love and love.keypressed then
    local love_keypressed_ref = love.keypressed
    function love.keypressed(key, ...)
        if key == "f6" and G and G.FUNCS and G.FUNCS.lkm_open_config then
            if not G.OVERLAY_MENU then
                G.FUNCS.lkm_open_config()
                return
            elseif Magician.overlay_open then
                G.FUNCS.lkm_exit_overlay()
                return
            end
        end
        return love_keypressed_ref(key, ...)
    end
end
