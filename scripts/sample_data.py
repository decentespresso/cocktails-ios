#!/usr/bin/env python3
"""Writes a small, made-up sample of the app's data into Resources/Data, for building and running
the app without the website's source tree (which scripts/sync_data.sh copies from and which is not
public).

    python3 scripts/sample_data.py

It writes the two book databases (pdt.db, deathco.db) in the schema the app's queries read, plus
the side JSON files. Everything in it is sample data: well-known classic drinks in everyday
proportions, written for this script, not the books' recipes, Decent's descriptions or the site's
figures. There are no pictures (cards show an empty picture box) and no translations (the app
falls back to English).

Use it to get the app running and to work on the code. To compare a page with the website, you
need the real data (scripts/sync_data.sh).

Python 3 standard library only.
"""
import json
import re
import sqlite3
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Resources" / "Data"

# ---------------------------------------------------------------------------------------------
# the schema: every table and column the app's SQL reads (Sources/Data, Sources/Members,
# Sources/Screens). Ingredient and glass ids are shared by the books; drink ids are not
# (Death & Co's start at 10001), as in Sources/Data/Books.swift. As on the site, each book holds
# only the ingredients its own drinks use.

SCHEMA = """
CREATE TABLE drink (drink_id INTEGER PRIMARY KEY, name TEXT NOT NULL, image TEXT);
CREATE TABLE ingredient (ingredient_id INTEGER PRIMARY KEY, name TEXT NOT NULL, image TEXT,
	bottle_img TEXT, generic TEXT, abv REAL, sugar REAL, acid REAL, sugar_per TEXT);
CREATE TABLE ingtag (ingredient_id INTEGER NOT NULL, name TEXT NOT NULL);
CREATE TABLE mixtype (mixtype_id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE quantity (quantity_id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE howto (howto_id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE step (drink_id INTEGER NOT NULL, ingredient_id INTEGER, mixtype_id INTEGER,
	quantity_id INTEGER, howto_id INTEGER, grams REAL, sortorder INTEGER);
CREATE TABLE glass (glass_id INTEGER PRIMARY KEY, name TEXT NOT NULL, image TEXT);
CREATE TABLE drink2glass (drink_id INTEGER NOT NULL, glass_id INTEGER NOT NULL);
CREATE TABLE popularity (drink_id INTEGER PRIMARY KEY, score INTEGER);
CREATE TABLE drink_stats (drink_id INTEGER PRIMARY KEY, volume_ml REAL, abv REAL, ethanol_ml REAL,
	ethanol_g REAL, vodka40_ml REAL, water_ml REAL, sugar_g REAL, sugar_pct REAL, acid_pct REAL,
	balance TEXT);
CREATE TABLE drink_book (drink_id INTEGER PRIMARY KEY, credit TEXT, source TEXT, date_text TEXT);
CREATE TABLE drink_description (drink_id INTEGER PRIMARY KEY, description TEXT);
CREATE TABLE drink_similar (drink_id INTEGER NOT NULL, similar_id INTEGER NOT NULL, rank INTEGER);
CREATE TABLE drink_similar_note (drink_id INTEGER NOT NULL, similar_id INTEGER NOT NULL,
	similar TEXT, different TEXT);
CREATE TABLE produce (produce_id INTEGER PRIMARY KEY, k TEXT NOT NULL, name TEXT NOT NULL, sortorder INTEGER);
CREATE TABLE produce_gives (produce_id INTEGER NOT NULL, ingredient_id INTEGER NOT NULL);
CREATE INDEX step_drink ON step(drink_id);
CREATE INDEX step_ing ON step(ingredient_id);
CREATE INDEX ingtag_ing ON ingtag(ingredient_id);
CREATE INDEX ingtag_name ON ingtag(name);
"""

# mix types: the app's code fixes these ids (Sources/Members/BarModel.swift: Garnish 2, Muddle 3,
# Rim 6, Spritz 8, Flame 9, Twist 10); the others it reads by name
MIXTYPES = {1: "Build", 2: "Garnish", 3: "Muddle", 4: "Top", 5: "Float", 6: "Rim", 7: "Rinse",
	8: "Spritz", 9: "Flame", 10: "Twist"}
MIX_ID = {v: k for k, v in MIXTYPES.items()}

# ingredients: name, tags, abv %, sugar and acid per 100 ml, the bar's kind (ingredient.generic),
# density (g/ml, for the steps' grams)
INGREDIENTS = [
	("London Dry Gin", ["gin"], 45, 0, 0, "gin", 0.94),
	("Rye Whiskey", ["whiskey"], 50, 0, 0, "whiskey", 0.93),
	("Bourbon Whiskey", ["whiskey"], 45, 0, 0, "whiskey", 0.94),
	("White Rum", ["rum"], 40, 0, 0, "rum", 0.95),
	("Aged Rum", ["rum"], 40, 0, 0, "rum", 0.95),
	("Blanco Tequila", ["tequila"], 40, 0, 0, "tequila", 0.95),
	("Reposado Tequila", ["tequila"], 40, 0, 0, "tequila", 0.95),
	("Vodka", ["vodka"], 40, 0, 0, "vodka", 0.95),
	("Mezcal", ["mezcal"], 45, 0, 0, "mezcal", 0.94),
	("Cognac", ["brandy"], 40, 0, 0, "brandy", 0.95),
	("Campari", ["liqueur"], 25, 24, 0, "", 1.05),
	("Orange Liqueur", ["liqueur"], 40, 25, 0, "orange_liqueur", 1.03),
	("Maraschino Liqueur", ["liqueur"], 32, 35, 0, "maraschino", 1.08),
	("Green Chartreuse", ["liqueur"], 55, 25, 0, "green_chartreuse", 1.0),
	("Sweet Vermouth", ["vermouth"], 16, 15, 0.6, "vermouth_sweet", 1.04),
	("Dry Vermouth", ["vermouth"], 17, 3, 0.6, "vermouth_dry", 0.99),
	("Lemon Juice", ["juice"], 0, 2.5, 6, "", 1.03),
	("Lime Juice", ["juice"], 0, 1.7, 6, "", 1.03),
	("Orange Juice", ["juice"], 0, 8.4, 0.8, "", 1.04),
	("Grapefruit Juice", ["juice"], 0, 6, 2.4, "grapefruit_juice", 1.04),
	("Pineapple Juice", ["juice"], 0, 10, 0.8, "", 1.05),
	("Simple Syrup", ["syrup"], 0, 61.5, 0, "", 1.23),
	("Demerara Syrup", ["syrup"], 0, 87, 0, "", 1.33),
	("Honey Syrup", ["syrup"], 0, 50, 0, "", 1.2),
	("Agave Syrup", ["syrup"], 0, 50, 0, "agave", 1.25),
	("Grenadine", ["syrup"], 0, 60, 0.5, "grenadine", 1.28),
	("Angostura Bitters", ["bitters"], 44.7, 4, 0, "", 0.95),
	("Orange Bitters", ["bitters"], 28, 2, 0, "bitters_orange", 0.97),
	("Peychaud's Bitters", ["bitters"], 35, 4, 0, "", 0.96),
	("Club Soda", ["mixer_soda"], 0, 0, 0, "", 1.0),
	("Ginger Beer", ["mixer_soda"], 0, 10, 0.3, "ginger_beer", 1.04),
	("Sparkling Wine", ["champagne"], 12, 1, 0.6, "sparkling", 1.0),
	("Egg White", ["egg"], 0, 0, 0, "", 1.03),
	("Mint Sprig", ["spice_herb_garnish"], 0, 0, 0, "", 1.0),
	("Mint Leaves", ["spice_herb_garnish"], 0, 0, 0, "", 1.0),
	("Lemon Twist", ["fruit"], 0, 0, 0, "", 1.0),
	("Orange Twist", ["fruit"], 0, 0, 0, "", 1.0),
	("Lime Wedge", ["fruit"], 0, 0, 0, "", 1.0),
	("Lime Wheel", ["fruit"], 0, 0, 0, "", 1.0),
	("Brandied Cherry", ["fruit"], 0, 0, 0, "", 1.0),
	("Cucumber Slice", ["vegetables"], 0, 0, 0, "", 1.0),
	("Kosher Salt", ["savory"], 0, 0, 0, "", 1.0),
	("Absinthe", ["absinthe"], 60, 0, 0, "absinthe", 0.92),
]
ING_ID = {row[0]: n for n, row in enumerate(INGREDIENTS, 1)}
ING = {row[0]: row for row in INGREDIENTS}

# what whole fruit gives (Your Bar's produce kinds)
PRODUCE = [
	("lemon", "Lemons", ["Lemon Juice", "Lemon Twist"]),
	("lime", "Limes", ["Lime Juice", "Lime Wedge", "Lime Wheel"]),
	("orange", "Oranges", ["Orange Juice", "Orange Twist"]),
]

GLASSES = ["Coupe", "Rocks", "Highball", "Collins", "Flute", "Nick & Nora", "Mug"]

SHAKE = "Shake with ice and strain"
SHAKE_DRY = "Dry shake, then shake with ice and strain"
STIR = "Stir with ice and strain"
BUILD = "Build over ice"
SWIZZLE = "Muddle, then build over crushed ice"

# drinks: name, method, glass, popularity, [(ingredient, book quantity, mix type)], description
# A quantity is "<n>oz", "<n>dashes", "<n>barspoon", a bare count for garnishes, or "" (to taste /
# top / rinse / rim). Every drink here is a well-known classic in everyday proportions.
PDT = [
	("Negroni", STIR, "Rocks", 98, [("London Dry Gin", "1oz", "Build"), ("Campari", "1oz", "Build"),
		("Sweet Vermouth", "1oz", "Build"), ("Orange Twist", "1", "Twist")],
		"Sample data: equal parts gin, Campari and sweet vermouth, bitter and bright."),
	("Martini", STIR, "Coupe", 95, [("London Dry Gin", "2.5oz", "Build"), ("Dry Vermouth", ".5oz", "Build"),
		("Orange Bitters", "1dash", "Build"), ("Lemon Twist", "1", "Twist")],
		"Sample data: gin with a little dry vermouth, stirred cold."),
	("Manhattan", STIR, "Coupe", 92, [("Rye Whiskey", "2oz", "Build"), ("Sweet Vermouth", "1oz", "Build"),
		("Angostura Bitters", "2dashes", "Build"), ("Brandied Cherry", "1", "Garnish")],
		"Sample data: rye and sweet vermouth with Angostura."),
	("Old Fashioned", STIR, "Rocks", 90, [("Bourbon Whiskey", "2oz", "Build"), ("Demerara Syrup", ".25oz", "Build"),
		("Angostura Bitters", "2dashes", "Build"), ("Orange Twist", "1", "Twist")],
		"Sample data: whiskey, a little sugar and bitters."),
	("Daiquiri", SHAKE, "Coupe", 88, [("White Rum", "2oz", "Build"), ("Lime Juice", "1oz", "Build"),
		("Simple Syrup", ".75oz", "Build"), ("Lime Wheel", "1", "Garnish")],
		"Sample data: rum, lime and sugar, shaken hard."),
	("Margarita", SHAKE, "Rocks", 87, [("Kosher Salt", "", "Rim"), ("Blanco Tequila", "2oz", "Build"),
		("Orange Liqueur", ".75oz", "Build"), ("Lime Juice", "1oz", "Build"), ("Lime Wedge", "1", "Garnish")],
		"Sample data: tequila, orange liqueur and lime, with a salted rim."),
	("Gimlet", SHAKE, "Coupe", 70, [("London Dry Gin", "2oz", "Build"), ("Lime Juice", ".75oz", "Build"),
		("Simple Syrup", ".75oz", "Build"), ("Lime Wheel", "1", "Garnish")],
		"Sample data: gin and lime, sweetened."),
	("Whiskey Sour", SHAKE_DRY, "Rocks", 80, [("Bourbon Whiskey", "2oz", "Build"), ("Lemon Juice", ".75oz", "Build"),
		("Simple Syrup", ".75oz", "Build"), ("Egg White", "1", "Build"), ("Angostura Bitters", "3dashes", "Garnish")],
		"Sample data: bourbon and lemon, silky with egg white."),
	("Tom Collins", SHAKE, "Collins", 60, [("London Dry Gin", "2oz", "Build"), ("Lemon Juice", "1oz", "Build"),
		("Simple Syrup", ".75oz", "Build"), ("Club Soda", "", "Top"), ("Lemon Twist", "1", "Garnish")],
		"Sample data: a tall gin sour topped with soda."),
	("Mojito", SWIZZLE, "Highball", 78, [("Mint Leaves", "8", "Muddle"), ("White Rum", "2oz", "Build"),
		("Lime Juice", "1oz", "Build"), ("Simple Syrup", ".75oz", "Build"), ("Club Soda", "", "Top"),
		("Mint Sprig", "1", "Garnish")],
		"Sample data: rum, lime and mint over crushed ice."),
	("French 75", SHAKE, "Flute", 75, [("London Dry Gin", "1oz", "Build"), ("Lemon Juice", ".5oz", "Build"),
		("Simple Syrup", ".5oz", "Build"), ("Sparkling Wine", "", "Top"), ("Lemon Twist", "1", "Twist")],
		"Sample data: a gin sour topped with sparkling wine."),
	("Paloma", BUILD, "Highball", 65, [("Kosher Salt", "", "Rim"), ("Blanco Tequila", "2oz", "Build"),
		("Grapefruit Juice", "2oz", "Build"), ("Lime Juice", ".5oz", "Build"), ("Agave Syrup", ".25oz", "Build"),
		("Club Soda", "", "Top"), ("Lime Wedge", "1", "Garnish")],
		"Sample data: tequila and grapefruit, long and salty."),
	("Sidecar", SHAKE, "Coupe", 68, [("Cognac", "1.5oz", "Build"), ("Orange Liqueur", ".75oz", "Build"),
		("Lemon Juice", ".75oz", "Build"), ("Orange Twist", "1", "Twist")],
		"Sample data: cognac, orange liqueur and lemon."),
	("Moscow Mule", BUILD, "Mug", 62, [("Vodka", "2oz", "Build"), ("Lime Juice", ".5oz", "Build"),
		("Ginger Beer", "", "Top"), ("Lime Wedge", "1", "Garnish")],
		"Sample data: vodka and lime with spicy ginger beer."),
	("Last Word", SHAKE, "Coupe", 58, [("London Dry Gin", ".75oz", "Build"), ("Green Chartreuse", ".75oz", "Build"),
		("Maraschino Liqueur", ".75oz", "Build"), ("Lime Juice", ".75oz", "Build")],
		"Sample data: equal parts gin, Chartreuse, maraschino and lime."),
	("Sazerac", STIR, "Rocks", 55, [("Absinthe", "", "Rinse"), ("Rye Whiskey", "2oz", "Build"),
		("Simple Syrup", ".25oz", "Build"), ("Peychaud's Bitters", "3dashes", "Build"),
		("Lemon Twist", "1", "Twist")],
		"Sample data: rye and Peychaud's in an absinthe-rinsed glass."),
	("Cucumber Gin Smash", SWIZZLE, "Rocks", 40, [("Cucumber Slice", "2", "Muddle"), ("London Dry Gin", "2oz", "Build"),
		("Lemon Juice", ".75oz", "Build"), ("Simple Syrup", ".5oz", "Build"), ("Cucumber Slice", "1", "Garnish")],
		"Sample data: gin and lemon with muddled cucumber."),
	# two base spirits (the spirit-pair pages)
	("Saratoga", STIR, "Coupe", 35, [("Rye Whiskey", "1oz", "Build"), ("Cognac", "1oz", "Build"),
		("Sweet Vermouth", "1oz", "Build"), ("Angostura Bitters", "2dashes", "Build"), ("Lemon Twist", "1", "Twist")],
		"Sample data: rye and cognac with sweet vermouth."),
	# every base spirit has a drink, so no spirit page is empty
	("Mezcal Sour", SHAKE_DRY, "Coupe", 38, [("Mezcal", "2oz", "Build"), ("Lime Juice", ".75oz", "Build"),
		("Agave Syrup", ".75oz", "Build"), ("Egg White", "1", "Build"), ("Angostura Bitters", "3dashes", "Garnish")],
		"Sample data: smoky mezcal and lime, silky with egg white."),
	# no base spirit (the "Other" group of the recipes by spirit)
	("Americano", BUILD, "Highball", 44, [("Campari", "1.5oz", "Build"), ("Sweet Vermouth", "1.5oz", "Build"),
		("Club Soda", "", "Top"), ("Orange Twist", "1", "Garnish")],
		"Sample data: Campari and sweet vermouth lengthened with soda."),
]

DEATHCO = [
	# the same name as in PDT but different amounts: "also in the other book", a different recipe
	("Negroni", STIR, "Rocks", 97, [("London Dry Gin", "1.5oz", "Build"), ("Campari", "1oz", "Build"),
		("Sweet Vermouth", "1oz", "Build"), ("Orange Twist", "1", "Twist")],
		"Sample data: a gin-forward Negroni."),
	# the same name and amounts as in PDT: "also in the other book", the same recipe
	("Margarita", SHAKE, "Rocks", 90, [("Kosher Salt", "", "Rim"), ("Blanco Tequila", "2oz", "Build"),
		("Orange Liqueur", ".75oz", "Build"), ("Lime Juice", "1oz", "Build"), ("Lime Wedge", "1", "Garnish")],
		"Sample data: tequila, orange liqueur and lime, with a salted rim."),
	("Mezcal Negroni", STIR, "Rocks", 80, [("Mezcal", "1oz", "Build"), ("Campari", "1oz", "Build"),
		("Sweet Vermouth", "1oz", "Build"), ("Orange Twist", "1", "Flame")],
		"Sample data: a smoky Negroni."),
	("Boulevardier", STIR, "Coupe", 82, [("Bourbon Whiskey", "1.5oz", "Build"), ("Campari", "1oz", "Build"),
		("Sweet Vermouth", "1oz", "Build"), ("Orange Twist", "1", "Twist")],
		"Sample data: a Negroni made with bourbon."),
	("Hemingway Daiquiri", SHAKE, "Coupe", 70, [("White Rum", "2oz", "Build"), ("Grapefruit Juice", ".75oz", "Build"),
		("Lime Juice", ".5oz", "Build"), ("Maraschino Liqueur", ".5oz", "Build")],
		"Sample data: a dry daiquiri with grapefruit and maraschino."),
	("Tommy's Margarita", SHAKE, "Rocks", 76, [("Reposado Tequila", "2oz", "Build"), ("Lime Juice", "1oz", "Build"),
		("Agave Syrup", ".5oz", "Build"), ("Lime Wedge", "1", "Garnish")],
		"Sample data: tequila, lime and agave, no liqueur."),
	("Bee's Knees", SHAKE, "Coupe", 66, [("London Dry Gin", "2oz", "Build"), ("Lemon Juice", ".75oz", "Build"),
		("Honey Syrup", ".75oz", "Build"), ("Lemon Twist", "1", "Twist")],
		"Sample data: gin, lemon and honey."),
	("Brown Derby", SHAKE, "Coupe", 52, [("Bourbon Whiskey", "2oz", "Build"), ("Grapefruit Juice", "1oz", "Build"),
		("Honey Syrup", ".5oz", "Build")],
		"Sample data: bourbon, grapefruit and honey."),
	("Gin Fizz", SHAKE_DRY, "Highball", 48, [("London Dry Gin", "2oz", "Build"), ("Lemon Juice", ".75oz", "Build"),
		("Simple Syrup", ".75oz", "Build"), ("Egg White", "1", "Build"), ("Club Soda", "", "Top")],
		"Sample data: a frothy gin sour lengthened with soda."),
	("Vodka Gimlet", SHAKE, "Coupe", 45, [("Vodka", "2oz", "Build"), ("Lime Juice", ".75oz", "Build"),
		("Simple Syrup", ".75oz", "Build"), ("Lime Wheel", "1", "Garnish")],
		"Sample data: vodka and lime, sweetened."),
	("Rum Old Fashioned", STIR, "Rocks", 50, [("Aged Rum", "2oz", "Build"), ("Demerara Syrup", ".25oz", "Build"),
		("Angostura Bitters", "2dashes", "Build"), ("Orange Twist", "1", "Twist")],
		"Sample data: an Old Fashioned with aged rum."),
	("Bramble Spritz", BUILD, "Flute", 30, [("Cognac", "1oz", "Build"), ("Lemon Juice", ".5oz", "Build"),
		("Grenadine", ".5oz", "Build"), ("Sparkling Wine", "", "Top"), ("Absinthe", "", "Spritz")],
		"Sample data: cognac and grenadine topped with sparkling wine, with an absinthe spritz."),
	("Split-Base Margarita", SHAKE, "Rocks", 42, [("Blanco Tequila", "1oz", "Build"), ("Mezcal", "1oz", "Build"),
		("Orange Liqueur", ".75oz", "Build"), ("Lime Juice", "1oz", "Build"), ("Lime Wedge", "1", "Garnish")],
		"Sample data: a Margarita split between tequila and mezcal."),
]

# similar drinks per book: (drink, similar, rank, hand-written note or None, taste note or None)
SIMILAR = {
	"pdt": [
		("Negroni", "Manhattan", 1, ("Both are stirred, spirit-forward and bittersweet.",
			"The Manhattan swaps gin and Campari for rye."), "The Manhattan is rounder and less bitter."),
		("Negroni", "Martini", 2, None, None),
		("Daiquiri", "Gimlet", 1, ("Both are a spirit, lime and sugar.", "Gin instead of rum."), "The Gimlet is more herbal."),
		("Daiquiri", "Margarita", 2, None, None),
		("Margarita", "Daiquiri", 1, None, None),
		("Whiskey Sour", "Gimlet", 1, None, None),
		("Tom Collins", "French 75", 1, None, None),
		("Old Fashioned", "Sazerac", 1, None, None),
	],
	"deathco": [
		("Negroni", "Boulevardier", 1, ("Both are equal-ish parts spirit, Campari and vermouth.",
			"Bourbon instead of gin."), "The Boulevardier is warmer and sweeter."),
		("Negroni", "Mezcal Negroni", 2, None, None),
		("Margarita", "Tommy's Margarita", 1, None, None),
		("Bee's Knees", "Brown Derby", 1, None, None),
	],
}

# what to use instead of a missing ingredient: {ingredient id: {name, subs: [{name, id, tip}], none}}
SUBSTITUTES = {
	"Rye Whiskey": [("Bourbon Whiskey", "Sweeter and softer.")],
	"Demerara Syrup": [("Simple Syrup", "Use a little less.")],
	"Honey Syrup": [("Agave Syrup", "Similar sweetness."), ("Simple Syrup", "Loses the honey flavour.")],
	"Orange Bitters": [("Angostura Bitters", "Spicier.")],
	"Mezcal": [("Blanco Tequila", "No smoke.")],
}

# ---------------------------------------------------------------------------------------------

def qty_ml(q, ing):
	"""a book amount in ml, as Store.qtyMl"""
	m = re.match(r"^([0-9.]+)(?:-([0-9.]+))?\s*([A-Za-z]*)$", q.strip())
	if not m:
		return 0.0
	a = float(m.group(1)); b = float(m.group(2) or m.group(1))
	n = (a + b) / 2; u = m.group(3).lower()
	ml = {"oz": 29.5735, "dash": 0.92, "dashes": 0.92, "drop": 0.05, "drops": 0.05, "barspoon": 5,
		"barspoons": 5, "tsp": 4.93, "tbsp": 14.79, "scoop": 60}
	if u in ml:
		return n * ml[u]
	return n * {"egg white": 30.0, "egg yolk": 18, "whole egg": 50}.get(ing.lower(), 0)

def is_count(q):
	return bool(q) and re.match(r"^[0-9][0-9./-]*$", q) is not None

def dil_kind(howto):
	"""Store.dilKind"""
	h = howto.lower().split(" or ")[0]
	has = lambda p: re.search(p, h) is not None
	if has("heat|warm|pre-heated|absinthe fountain|drip"): return "none"
	if has("shake|swizzle|blend|whip"): return "shake"
	if has("stir|ice|build|crushed|pebble"): return "stir"
	return "none"

def topped_ml(ing):
	"""what a 'Top' with no amount is taken as (Store.recipe): 60 ml of sparkling, 90 of soda"""
	if re.search(r"champagne|sparkling|prosecco|cava|cider", ing, re.I): return 60.0
	if re.search(r"soda|tonic|seltzer|cola|ginger beer|ginger ale", ing, re.I): return 90.0
	return 0.0

def stats(howto, steps):
	"""drink_stats from the steps, with the scale maker's model (Maker.drinkFacts)"""
	bv = be = tv = te = sg = ac = 0.0
	for ing, q, mix in steps:
		ml = mix.lower()
		if ml in ("garnish", "twist", "rim", "spritz", "rinse"):
			continue
		v = topped_ml(ing) if (ml == "top" and not q) else qty_ml(q, ing)
		_, _, abv, sugar, acid, _, _ = ING[ing]
		e = v * abv / 100
		sg += v * sugar / 100; ac += v * acid / 100
		if ml in ("top", "float", "flame"): tv += v; te += e
		else: bv += v; be += e
	a = be / bv if bv else 0
	k = dil_kind(howto)
	w = bv * (1.567 * a * a + 1.742 * a + 0.203) if k == "shake" else (bv * (-1.21 * a * a + 1.246 * a + 0.145) if k == "stir" else 0)
	vol = bv + w + tv; eth = be + te
	sp = 100 * sg / vol; ap = 100 * ac / vol
	if ap >= 0.4:
		r = sp / ap; bal = "Tart" if r < 6 else ("Balanced" if r < 12 else "Sweet")
	else:
		bal = "Dry" if sp < 2 else ("Off-dry" if sp < 5 else ("Sweet" if sp < 10 else "Very sweet"))
	return (round(vol, 1), round(100 * eth / vol, 1), round(eth, 1), round(eth * 0.789, 1), round(eth / 0.4, 1),
		round(w, 1), round(sg, 1), round(sp, 2), round(ap, 2), bal)

def build(book, drinks, first_id, credit):
	path = OUT / f"{book}.db"
	if path.exists():
		path.unlink()
	db = sqlite3.connect(path)
	db.executescript(SCHEMA)
	db.executemany("INSERT INTO mixtype VALUES (?,?)", MIXTYPES.items())
	used = {ing for d in drinks for ing, _, _ in d[4]}
	for name, tags, abv, sugar, acid, generic, _ in INGREDIENTS:
		if name not in used:
			continue
		iid = ING_ID[name]
		db.execute("INSERT INTO ingredient VALUES (?,?,?,?,?,?,?,?,?)",
			(iid, name, None, None, generic or None, abv, sugar, acid, "100ml"))
		db.executemany("INSERT INTO ingtag VALUES (?,?)", [(iid, t) for t in tags])
	for n, (k, nm, gives) in enumerate(PRODUCE, 1):
		gives = [g for g in gives if g in used]
		if not gives:
			continue
		db.execute("INSERT INTO produce VALUES (?,?,?,?)", (n, k, nm, n))
		db.executemany("INSERT INTO produce_gives VALUES (?,?)", [(n, ING_ID[g]) for g in gives])
	db.executemany("INSERT INTO glass VALUES (?,?,?)", [(n, g, None) for n, g in enumerate(GLASSES, 1)])
	glass_id = {g: n for n, g in enumerate(GLASSES, 1)}

	quantities, howtos = {}, {}
	def qid(q):
		if not q: return None
		if q not in quantities:
			quantities[q] = len(quantities) + 1
			db.execute("INSERT INTO quantity VALUES (?,?)", (quantities[q], q))
		return quantities[q]
	def hid(h):
		if h not in howtos:
			howtos[h] = len(howtos) + 1
			db.execute("INSERT INTO howto VALUES (?,?)", (howtos[h], h))
		return howtos[h]

	ids = {}
	for n, (name, howto, glass, pop, steps, descr) in enumerate(drinks):
		did = first_id + n
		ids[name] = did
		db.execute("INSERT INTO drink VALUES (?,?,?)", (did, name, None))
		db.execute("INSERT INTO drink2glass VALUES (?,?)", (did, glass_id[glass]))
		db.execute("INSERT INTO popularity VALUES (?,?)", (did, pop))
		db.execute("INSERT INTO drink_description VALUES (?,?)", (did, descr))
		db.execute("INSERT INTO drink_book VALUES (?,?,?,?)", (did, credit, "", ""))
		for so, (ing, q, mix) in enumerate(steps, 1):
			grams = None
			if q and not (is_count(q) and mix in ("Garnish", "Twist", "Flame")):
				ml = qty_ml(q, ing)
				if ml:
					grams = round(ml * ING[ing][6], 1)
			db.execute("INSERT INTO step VALUES (?,?,?,?,?,?,?)",
				(did, ING_ID[ing], MIX_ID[mix], qid(q), hid(howto), grams, so))
		db.execute("INSERT INTO drink_stats VALUES (?,?,?,?,?,?,?,?,?,?,?)", (did,) + stats(howto, steps))

	taste = []
	for a, b, rank, note, t in SIMILAR[book]:
		db.execute("INSERT INTO drink_similar VALUES (?,?,?)", (ids[a], ids[b], rank))
		if note:
			db.execute("INSERT INTO drink_similar_note VALUES (?,?,?,?)", (ids[a], ids[b]) + note)
		if t:
			taste.append({"did": ids[a], "sid": ids[b], "taste": t})
	(OUT / f"{book}_similar_taste.json").write_text(json.dumps(taste, indent=1))
	db.commit()
	db.close()
	return len(drinks)

def main():
	OUT.mkdir(parents=True, exist_ok=True)
	n = build("pdt", PDT, 1, "Sample data")
	n += build("deathco", DEATHCO, 10001, "Sample data")
	subs = {str(ING_ID[k]): {"name": k, "subs": [{"name": s, "id": ING_ID[s], "tip": tip} for s, tip in v], "none": ""}
		for k, v in SUBSTITUTES.items()}
	(OUT / "ingredient_substitutes.json").write_text(json.dumps(subs, indent=1))
	print(f"Wrote sample data to {OUT}: {n} drinks, {len(INGREDIENTS)} ingredients. "
		"No pictures or translations; run scripts/sync_data.sh for the real data.")

if __name__ == "__main__":
	main()
