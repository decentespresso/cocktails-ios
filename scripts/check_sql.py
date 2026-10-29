#!/usr/bin/env python3
"""Runs every SQL query in Sources/ against the bundled book databases (Resources/Data), so a
change to the app's queries or to the data's schema is caught without building the app:

    python3 scripts/check_sql.py

It finds each Swift string literal that holds a SELECT, fills its \\(...) interpolations with
what the app would put there, binds ?1, ?2 ... with a value that suits the column before it,
and runs it on pdt.db and deathco.db. It fails if any query does not run; a query that runs but
returns no rows is listed, as the data may simply have none.

Works with the real data (scripts/sync_data.sh) or the sample (scripts/sample_data.py).
Python 3 standard library only.
"""
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "Resources" / "Data"
BASE = ["gin", "whiskey", "rum", "tequila", "vodka", "mezcal", "brandy"]

def garnish_only(col):
	"""Store.garnishOnlySQL"""
	return (f"(EXISTS (SELECT 1 FROM step gs WHERE gs.ingredient_id={col}) AND NOT EXISTS (SELECT 1 FROM step gs "
		f"JOIN mixtype gm ON gm.mixtype_id=gs.mixtype_id WHERE gs.ingredient_id={col} AND lower(gm.name) NOT IN "
		f"('garnish','twist','rim')) AND NOT EXISTS (SELECT 1 FROM ingtag gt WHERE gt.ingredient_id={col} AND gt.name='dairy_cream'))")

def quoted(xs):
	return ",".join(f"'{x}'" for x in xs)

# what the app interpolates; a literal with any other \(...) is reported, so it gets added here
INTERP = {
	"bsin": quoted(BASE), "bs": quoted(BASE), "stin": quoted(["liqueur", "syrup"]),
	"catin": quoted(["juice", "syrup", "liqueur", "fruit"]), "table": "drink",
	"notg": "", "notgs": "", "spiritCond":
		"EXISTS (SELECT 1 FROM step s JOIN ingtag t ON t.ingredient_id=s.ingredient_id WHERE s.drink_id=d.drink_id AND t.name=?1)",
	"usesql": "EXISTS (SELECT 1 FROM step s JOIN ingtag t ON t.ingredient_id=s.ingredient_id WHERE s.drink_id=d.drink_id AND t.name=?1)",
	"ingsql": "SELECT 1",
}

def fill(sql):
	missing = []
	def rep(m):
		expr = m.group(1)
		g = re.fullmatch(r'Store\.garnishOnlySQL\("([^"]+)"\)', expr)
		if g:
			return garnish_only(g.group(1))
		if expr in INTERP:
			return INTERP[expr]
		missing.append(expr)
		return "NULL"
	return re.sub(r"\\\(((?:[^()]|\([^()]*\))*)\)", rep, sql), missing

def literals(text):
	"""Swift string literals: multi-line \"\"\" ones, then single-line ones"""
	out = []
	for m in re.finditer(r'"""\n(.*?)\n\s*"""', text, re.S):
		body = m.group(1)
		indent = min((len(l) - len(l.lstrip("\t ")) for l in body.splitlines() if l.strip()), default=0)
		out.append((m.start(), "\n".join(l[indent:] for l in body.splitlines())))
	text = re.sub(r'"""\n.*?\n\s*"""', lambda m: " " * len(m.group(0)), text, flags=re.S)
	i = 0
	while i < len(text):
		if text[i] != '"':
			i += 1
			continue
		start, i, buf = i, i + 1, []
		while i < len(text) and text[i] not in '"\n':
			if text.startswith("\\(", i):
				# an interpolation: up to its closing paren, quotes and parens inside included
				j, depth, inq = i + 2, 1, False
				while j < len(text) and depth:
					c = text[j]
					if c == '"': inq = not inq
					elif not inq and c == "(": depth += 1
					elif not inq and c == ")": depth -= 1
					j += 1
				buf.append(text[i:j]); i = j
			elif text[i] == "\\":
				buf.append(text[i:i + 2]); i += 2
			else:
				buf.append(text[i]); i += 1
		out.append((start, "".join(buf)))
		i += 1
	return out

def param(before):
	"""a value for ?N from the SQL just before it"""
	b = before.lower().rstrip()
	if b.endswith("limit"): return -1
	if "like" in b[-6:]: return "%lime%"
	col = re.search(r"([a-z0-9_.]+)\s*(=|!=|<>)\s*$", b)
	c = col.group(1) if col else ""
	if c.endswith("drink_id") or c.endswith("similar_id"): return 1
	if c.endswith("ingredient_id"): return 18
	if c.endswith("balance"): return "Balanced"
	if c in ("g.name",): return "Coupe"
	if c in ("t.name", "t2.name", "t5.name", "t1.name"): return "gin"
	if c in ("i.name", "i1.name", "i2.name", "name") and "from drink" in b and "ingredient" not in b: return "Negroni"
	if c in ("i.name", "i1.name", "i2.name", "name"): return "Lime Juice"
	return "gin"

def args_for(sql):
	n = max((int(x) for x in re.findall(r"\?(\d+)", sql)), default=0)
	vals = []
	for k in range(1, n + 1):
		pos = sql.find(f"?{k}")
		v = param(sql[:pos])
		# ?2 next to ?1 on the same kind of column: a second, different value
		if k == 2 and v == "gin": v = "liqueur"
		if k == 2 and v == "Lime Juice": v = "Simple Syrup"
		vals.append(v)
	return vals

def main():
	books = [p for p in (DATA / "pdt.db", DATA / "deathco.db") if p.exists()]
	if not books:
		sys.exit("No databases in Resources/Data: run scripts/sample_data.py or scripts/sync_data.sh first.")
	dbs = {p.stem: sqlite3.connect(f"file:{p}?mode=ro", uri=True) for p in books}
	failed, empty, ran, unmapped = [], [], 0, set()
	for f in sorted((ROOT / "Sources").rglob("*.swift")):
		text = f.read_text()
		for pos, lit in literals(text):
			if not re.match(r"\s*SELECT\b", lit, re.I):
				continue
			line = text.count("\n", 0, pos) + 1
			sql, missing = fill(lit)
			if missing:
				unmapped.update(missing)
				continue
			if re.search(r"\b(FROM|WHERE|AND|OR)\s*$", sql.strip(), re.I) or sql.rstrip().endswith("IN ("):
				continue
			args = args_for(sql)
			where = f"{f.relative_to(ROOT)}:{line}"
			counts = []
			for name, db in dbs.items():
				try:
					counts.append(len(db.execute(sql, args).fetchall()))
				except sqlite3.Error as e:
					failed.append(f"{where} ({name}.db): {e}\n    {' '.join(sql.split())[:200]}")
					counts = None
					break
			ran += 1
			if counts is not None and not any(counts):
				empty.append(f"{where}: {' '.join(sql.split())[:110]}  args={args}")
	print(f"{ran} queries run on {', '.join(p.name for p in books)}")
	if unmapped:
		print("\nNot run, unknown interpolations (add them to INTERP):", ", ".join(sorted(unmapped)))
	if empty:
		print(f"\nRan but returned no rows in any book ({len(empty)}):")
		for e in empty: print("  " + e)
	if failed:
		print(f"\nFAILED ({len(failed)}):")
		for e in failed: print("  " + e)
		sys.exit(1)
	print("\nEvery query ran.")

if __name__ == "__main__":
	main()
