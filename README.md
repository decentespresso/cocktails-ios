# Decent Cocktails for iPhone, iPad and Mac

A native SwiftUI app of [Decent Cocktails](https://decentespresso.com/cocktails/): cocktail recipes from *The PDT Cocktail Book* and *Death & Co: Modern Classic Cocktails*, each ingredient weighed in grams and made to be mixed on the [Half Decent Scale](https://decentespresso.com/scale).

The app is a copy of the website, page for page. It ships with the books' databases and pictures, so it works without a network connection.

Status: a work in progress, not yet in the App Store. It runs as a Mac Catalyst app (for debugging) and on iPhone and iPad.

## What it does

- **Browse:** choose a book, then browse its cocktails by popularity, A–Z, base spirit or sweetness, by spirit and spirit pairs ("gin + Campari"), by ingredient and ingredient type, and by glass. Search covers drinks, ingredients and spirit types.
- **Recipes:** every step in grams (and ounces), the glass and method, and Decent's own description. Each recipe also has alcohol, sugar and acid figures, similar cocktails with how they differ, and the same drink in the other book. Tap a photo to see it larger, as on the site.
- **Members:** sign in with a decentespresso.com account (OAuth, client `cocktails-ios`) for Your Bar, the Wishlist and the Made list with notes. They are the same data the website keeps, so a change on one shows on the other.
- **The Half Decent Scale:** make a drink step by step over Bluetooth. Each step tares the scale and shows what to pour, and the end screen compares your drink with the recipe.
- **Languages:** the website's own translations (German, French, Spanish, Korean, Arabic, Simplified and Traditional Chinese), from the globe menu or the device language. Light and dark mode follow the system.

Planned: iPhone and iPad polish, and the App Store.

## Building

You need Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/sync_data.sh
```

```bash
xcodegen generate
```

```bash
xcodebuild -scheme Cocktails -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build CODE_SIGN_IDENTITY=- build
```

Or open `Cocktails.xcodeproj` in Xcode and run on an iPhone simulator or "My Mac (Mac Catalyst)".

`scripts/sync_data.sh` copies the data into `Resources/Data/`:
- the two book databases (`pdt.db`, `deathco.db`, SQLite)
- the taste and substitute notes (JSON)
- the AVIF pictures
- the translations (`lang/<code>.json`), which `scripts/sync_lang.py` reads from the website's phrase table (it needs a Decent admin API token)

These come from the website's source tree (`/d`), which is not public. That is why the data is not in this repository (see Licence).

### Without the website's data

To build and run the app without the website's tree, make sample data instead of running `scripts/sync_data.sh`:

```bash
python3 scripts/sample_data.py
```

It writes the two book databases and the JSON files in the same schema, with about 30 well-known classic drinks in everyday proportions. They are made up for the script, not the books' recipes or Decent's descriptions, and there are no pictures or translations. That is enough to work on the code, but not to compare a page with the website.

`scripts/check_sql.py` runs every query in `Sources/` against whichever data is in `Resources/Data/`, so a change to a query or to the schema shows up without building the app. Run it after changing either.

GitHub Actions does all of this on every push and pull request (`.github/workflows/build.yml`): it makes the sample data, runs `scripts/check_sql.py`, and builds for Mac Catalyst and the iOS Simulator.

## How it is put together

```
project.yml              XcodeGen spec; the .xcodeproj is generated from it
Sources/
  CocktailsApp.swift     the app, the navigation stack, deep links, the book header
  Data/
    SQLite.swift         a small read-only SQLite wrapper
    Books.swift          the books (as pdt_books on the site)
    Store.swift          a book's queries: spirits, categories, glasses, search, cards
    Recipe.swift         one recipe: the steps in grams, serve row, facts, similar drinks
    Img.swift            where pictures are (the db's image column), and the site's full-size copies
    Lang.swift           the language, T() / TM() lookups in the site's phrase table
  Members/
    Account.swift        sign-in (OAuth + PKCE), the token in the Keychain, the site's permacookies
    Member.swift         Wishlist, Made, notes, Your Bar: read and written like the website
    BarModel.swift       Your Bar's maths (a port of the site's bar.js)
  Maker/
    Scale.swift          the Half Decent Scale over Bluetooth (and a pretend one for testing)
    Maker.swift          the weighing steps (a port of the site's scale_maker.js)
  UI/
    Theme.swift          the site's colours and fonts, light and dark
    Route.swift          every page as a route, and site URL → route
    Components.swift     cards, chips, grids, section heads
  Screens/               the pages: home, lists, recipe, Your Bar, the scale maker
scripts/
  sync_data.sh           copy the dbs and pictures from the site's tree
  sync_lang.py           the site's translations of every phrase the app shows
  sample_data.py         made-up sample data, for building without the site's tree
  check_sql.py           run every query in Sources/ against the data
  shot.sh                screenshot any page of the Mac build: shot.sh /cocktails/pdt/recipes/Negroni out.png
```

Each page runs the same SQL as the website's page (`lib/direct.tcl` on the site), so the two list the same drinks in the same order. The app takes the site's paths as deep links and as a launch argument:

```bash
"build/Build/Products/Debug-maccatalyst/Decent Cocktails.app/Contents/MacOS/Decent Cocktails" -open /cocktails/deathco/spirit/gin
```

Debug builds take a few more launch arguments:
- `-lang de`: start in a language
- `-fakescale 1 -maker 1`: open the scale maker on the `-open` recipe with a pretend scale that pours by itself
- `-server http://localhost:8000 -token <bearer>`: use a development website and account
- `-dumpbar <book>` and `-checkfacts 1`: print Your Bar's and the maker's numbers for comparing with the website, then quit

Pictures are named by the `image` column of the `drink`, `ingredient` and `glass` tables: the path below `cocktails/img/` without the extension, e.g. `deathco/negroni`. The [API guide](https://decentespresso.com/cocktails/api/) lists every size and copy of a picture.

## Licence

The **app's source code** is licensed under the GNU General Public License, version 3: see [LICENSE](LICENSE).

The licence covers the code only, not the data the app ships with:
- **Decent's own content:** the drink descriptions, comparisons and taste notes, method wording, computed figures, and the AI-generated drink and glass pictures. It is Creative Commons Attribution 4.0 ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)), credit "Decent Cocktails (decentespresso.com/cocktails)".
- **The recipe facts:** drink names, ingredients and amounts, glass, garnish and creator credits. They come from the books, and Decent claims no rights in them. Please buy the books.
- **Ingredient pictures:** many are product photographs, or drawn from them, and show the makers' labels. They are not licensed for reuse.
- **Fonts:** [Archivo](https://fonts.google.com/specimen/Archivo) and [IBM Plex Mono](https://fonts.google.com/specimen/IBM+Plex+Mono), under the SIL Open Font License 1.1.

To build your own app from the same recipes, use the public [Decent Cocktails API](https://decentespresso.com/cocktails/api/) or its [MCP server](https://decentespresso.com/cocktails/mcp).

© Decent Espresso Ltd
