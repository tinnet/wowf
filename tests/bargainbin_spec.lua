-- BargainBin's arithmetic (BargainBin/Logic.lua). Plain data only.
local ns = {}
assert(loadfile("BargainBin/Logic.lua"))("BargainBin", ns)
local Logic = ns.Logic

describe("profit", function()
    it("is vendor price times stack minus buyout", function()
        assert.equal(280, Logic.profit(5, 100, 220))
    end)

    it("is nothing without a buyout or a vendor price", function()
        assert.equal(0, Logic.profit(5, 10, 0))
        assert.equal(0, Logic.profit(0, 10, 1))
        assert.equal(0, Logic.profit(nil, 10, 1))
    end)
end)

describe("collecting deals from the dump", function()
    it("keeps only auctions under vendor price, summed per item", function()
        local deals = {}
        Logic.add(deals, 4390, 100, 22000, 500) -- Iron Grenade: 28000 profit
        Logic.add(deals, 4390, 10, 5000, 500) -- exactly vendor price: no profit
        Logic.add(deals, 4390, 10, 1780, 500) -- 3220 profit
        Logic.add(deals, 3864, 1, 633, 800) -- Citrine: 167 profit
        Logic.add(deals, 2852, 1, 400, 403) -- 3 copper under: not worth a click
        Logic.add(deals, 770, 1, 400, 316) -- over vendor price
        local list = Logic.sorted(deals)
        assert.equal(2, #list)
        assert.same({
            itemID = 4390,
            auctions = 2,
            units = 110,
            cost = 23780,
            value = 55000,
            profit = 31220,
        }, list[1])
        assert.equal(3864, list[2].itemID)
    end)
end)

describe("offers from an item search", function()
    local results = {
        { auctionID = 1, quantity = 10, buyoutAmount = 2000 }, -- 3000
        { auctionID = 2, quantity = 20, buyoutAmount = 2000 }, -- 8000
        { auctionID = 3, quantity = 10, buyoutAmount = 6000 }, -- loses money
        { auctionID = 4, quantity = 10, buyoutAmount = 1000, containsOwnerItem = true },
        { auctionID = 5, quantity = 10 }, -- bid only
        { auctionID = 6, quantity = 5, buyoutAmount = 100 }, -- 2400
        { auctionID = 7, quantity = 1, buyoutAmount = 497 }, -- 3: too little
    }

    it("lists those that pay, best first, never your own", function()
        local offers = Logic.offers(results, 500)
        assert.same({ 2, 1, 6 }, {
            offers[1].auctionID,
            offers[2].auctionID,
            offers[3].auctionID,
        })
        assert.equal(8000, offers[1].profit)
    end)

    it("skips auctions already bought", function()
        local offers = Logic.offers(results, 500, { [2] = true })
        assert.equal(1, offers[1].auctionID)
        assert.equal(2, #offers)
    end)
end)

describe("commodity units", function()
    it("takes the cheapest units up to the first that doesn't pay", function()
        local units, cost = Logic.commodityUnits({
            { quantity = 30, unitPrice = 178 },
            { quantity = 10, unitPrice = 400 },
            { quantity = 5, unitPrice = 500 },
            { quantity = 50, unitPrice = 100 }, -- never reached: not how the game sorts
        }, 500)
        assert.equal(40, units)
        assert.equal(30 * 178 + 10 * 400, cost)
    end)

    it("stops at your own listing, which a purchase can't skip", function()
        local units = Logic.commodityUnits({
            { quantity = 3, unitPrice = 100, containsOwnerItem = true },
            { quantity = 30, unitPrice = 178 },
        }, 500)
        assert.equal(0, units)
    end)
end)
