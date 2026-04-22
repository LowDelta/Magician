return {
    master_enabled    = true,
    intensity         = 50,    -- 0 .. 100 (percent) - main luck meter
    shrink            = 100,   -- 0 .. 100 (percent) - how hard hits-luck collapses a pseudorandom roll

    rarity_luck       = true,  -- bias joker rarity rolls upward
    edition_luck      = true,  -- boost edition chances (foil/holo/poly/neg)
    allow_negative    = true,  -- allow Negative edition in boosted roll

    seal_luck         = true,  -- more seals, biased to rarer
    tag_luck          = true,  -- reroll chance for rarer skip tags
    voucher_luck      = true,  -- reroll chance for vouchers
    pack_luck         = true,  -- upgrade booster packs (Normal->Jumbo->Mega)

    soul_luck         = true,  -- boost Soul / Black Hole odds when soulable

    hits_luck         = true,  -- boost all probability-based triggers (Lucky Card, 8-Ball, Bloodstone, etc.)
    no_negative_hits  = true,  -- protect against negative rolls (Gros Michel / Cavendish dying)

    bias_towards_run  = true,  -- detect deck archetype and favor matching jokers in shops
}
