# Analyse: insights.nvim ↔ documentation.nvim ↔ runtime-analysis.nvim

**Befund vorweg:** Aktuell gibt es **null Querverweise** zwischen insights.nvim und den beiden anderen — weder im Code noch in der Doku. documentation.nvim und runtime-analysis.nvim dagegen sind bereits eng verzahnt, mit einem eigenen Architektur-Dokument dafür ([`documentation.nvim/docs/ROADMAP/FEATURES/ECOSYSTEM.md`](C:\repos\documentation.nvim\docs\ROADMAP\FEATURES\ECOSYSTEM.md)) und einem Ideen-Backlog nur für die Schnittstelle zwischen den beiden ([`runtime-analysis.nvim/docs/IDEAS.md`](C:\repos\runtime-analysis.nvim\docs\IDEAS.md)). insights.nvim ist dort mit keiner Silbe erwähnt. Das ist der Ausgangspunkt der Analyse.

## Table of content

  - [1. Was die drei Plugins tatsächlich sind](#1-was-die-drei-plugins-tatschlich-sind)
  - [2. Echte Überschneidungen (Duplizierungsrisiko)](#2-echte-berschneidungen-duplizierungsrisiko)
  - [3. Konkrete Synergie-Chancen, nach Aufwand/Nutzen sortiert](#3-konkrete-synergie-chancen-nach-aufwandnutzen-sortiert)
  - [4. Was bewusst **nicht** sinnvoll ist](#4-was-bewusst-nicht-sinnvoll-ist)
  - [Kurzfazit](#kurzfazit)

---

## 1. Was die drei Plugins tatsächlich sind

| Plugin | Kernidee | Reichweite | Datenbasis |
|---|---|---|---|
| **documentation.nvim** | Statische Wahrheit: was existiert, was ist dokumentiert, wie hängt es zusammen | **Lua-only**, nur `---@module`-annotierte Bäume | Persistiertes, byte-deterministisches IR (`module_map.json`), CI-geprüft |
| **runtime-analysis.nvim** | Laufzeit-Wahrheit: was tatsächlich ausgeführt wurde | Lua/Neovim-Plugins (Telemetry), plus HTTP-Request-Runner | Live-Zähler im Prozess, persistiert im Cache |
| **insights.nvim** | Ad-hoc-Projektanalyse: Symbole, Metriken, Imports/Deps, Baum, Komprimierung | **11 Sprachen** (Symbole), **6 Sprachen** (Imports) — ausdrücklich nicht nur Lua/Neovim | ripgrep + punktuelles Tree-sitter, kein persistiertes IR, kein CI-Gate |

Die beiden etablierten Plugins organisieren sich entlang einer klaren Naht ("Seam A: static vs. runtime", [ECOSYSTEM.md](C:\repos\documentation.nvim\docs\ROADMAP\FEATURES\ECOSYSTEM.md):87-92). insights.nvim liegt komplett auf der statischen Seite — aber auf einer **anderen Achse**, die in deren Dokumenten so nicht benannt ist:

> **Tief & eng vs. breit & flach.** documentation.nvim ist tief (persistiertes IR, Call-Graphen, Drift-Checks, CI-gated) aber eng (nur Lua, nur annotierter Code). insights.nvim ist breit (6–11 Sprachen) aber flach (Textscan/Regex, keine Historie, kein Determinismus-Anspruch).

Das ist keine Konkurrenzsituation, sondern eine echte Arbeitsteilung — vorausgesetzt, man macht sie sichtbar.

---

## 2. Echte Überschneidungen (Duplizierungsrisiko)

Zwei Stellen, an denen insights.nvim bereits **das baut, was documentation.nvim sich für später vorgenommen hat**:

- **`:Insights imports unused`** ([commands.md:249-259](C:\repos\insights.nvim\docs\commands.md)) — gebundene Import-Namen, die nie wieder referenziert werden. documentation.nvim listet exakt das als offene Idee: *"Unused requires … cheap: the IR already has both the require edges and the symbol references"* ([documentation.nvim IDEAS.md §2.5](C:\repos\documentation.nvim\docs\ROADMAP\IDEAS\IDEAS.md):244-249). Würde das dort gebaut, entstünde eine Zweitimplementierung derselben Funktion — nur enger (Lua-only) und ohne die anderen 5 Sprachen, die insights.nvim schon abdeckt.
- **`:Insights symbols`** — ripgrep-basierter Symbolindex über 11 Sprachen mit Telescope/fzf-Picker. documentation.nvim hat "Workspace symbols from the IR" bewusst verworfen: *"Whether this is worth building depends entirely on whether it beats lua-language-server … Probably not"* ([IDEAS.md §6.5](C:\repos\documentation.nvim\docs\ROADMAP\IDEAS\IDEAS.md):445-451) — aber genau für Lua, wo LSP ohnehin gut ist. Für die anderen 10 Sprachen in insights.nvim, wo kein/schlechteres LSP-Workspace-Symbol existiert, füllt insights.nvim eine Lücke, die documentation.nvim strukturell nie schließen wird (Lua-only per Design).

**Konsequenz:** Bevor documentation.nvim `IDEAS.md §2.5` angeht, lohnt ein Blick auf insights.nvim — evtl. reicht ein Verweis statt Neubau.

---

## 3. Konkrete Synergie-Chancen, nach Aufwand/Nutzen sortiert

**a) READMEs gegenseitig verlinken (trivial, sofort sinnvoll)**
insights.nvim pairt aktuell nur mit `buffer-ctx.nvim` ([README.md:11-13](C:\repos\insights.nvim\README.md)). Ein ehrlicher Hinweis in beide Richtungen — *"für reines Lua/Neovim-Plugin-Dokumentieren mit IR/CI-Gate: documentation.nvim; für schnelle Ad-hoc-Analyse über mehrere Sprachen hinweg: insights.nvim"* — verhindert genau die Duplizierung aus Punkt 2 und hilft Nutzern bei der Werkzeugwahl.

**b) insights.nvim mit `runtime-analysis.telemetry` selbst instrumentieren**
runtime-analysis.nvim bietet genau dafür einen generischen Helfer: `telemetry.auto({ namespace, main, deep })` — "new+wrap+start in einem Call", soft-dependency, No-op ohne das Plugin ([telemetry/README.md:206-233](C:\repos\runtime-analysis.nvim\lua\runtime-analysis\telemetry\README.md)). documentation.nvim macht das bereits mit sich selbst (`telemetry_self`, [ECOSYSTEM.md:704-724](C:\repos\documentation.nvim\docs\ROADMAP\FEATURES\ECOSYSTEM.md)) — exakt dasselbe Muster wie der schon vorhandene `deps_popup`-Opt-out in [DEFAULTS.lua:192-198](C:\repos\insights.nvim\lua\insights\config\DEFAULTS.lua). Ein `opts.telemetry = true`-Default (No-op ohne runtime-analysis.nvim) würde beantworten: *Welche `:Insights`-Subcommands werden überhaupt benutzt?* — relevant z. B. für die Frage, ob `compress` oder `devserver` das Gewicht im Plugin wert sind.

**c) insights.nvim dev-only mit documentation.nvim mappen**
Sowohl documentation.nvim als auch runtime-analysis.nvim generieren ihre eigene `docs/map/` und veröffentlichen sie (READMEs, jeweils "This repository maps itself with the same tool"). insights.nvim pflegt [`docs/architecture.md`](C:\repos\insights.nvim\docs\architecture.md) dagegen **von Hand** — genau die Art Dokument, die documentation.nvim ersetzen soll (Drift zwischen Doku und Code automatisch erkennen, statt sie manuell synchron zu halten). Kostet nur `dev-dependency` + `scripts/gen_map.lua`, kein Laufzeit-Impact.

**d) Metrics-Report optional um documentation.nvim-Kennzahlen erweitern**
`:Insights metrics` schreibt bereits nach Datei/PDF ([commands.md:59-99](C:\repos\insights.nvim\docs\commands.md), PDF-Export kam gerade erst dazu, siehe letzter Commit). Falls im Projekt ein `docs/map/module_map.json` existiert (rein lesend, `pcall`, kein Hard-Dependency), könnte der Report eine zusätzliche Sektion mit documentation.nvim's Strukturkennzahlen (Zyklomatische Komplexität, Fan-in/out, Duplikate, Doc-Coverage) übernehmen — statt sie neu zu berechnen. insights.nvim liefert dann Text-/Wort-Statistik, documentation.nvim liefert Struktur — ein gemeinsamer Report ohne Codeverdopplung.

**e) Polyglotter Imports-Graph als dokumentierter Fallback**
`:Insights imports graph` zeichnet bereits Abhängigkeitsgraphen für Python/Go/Rust/C/C++ ([commands.md:273-301](C:\repos\insights.nvim\docs\commands.md)) — Sprachen, die documentation.nvim's Backend laut eigenem [`docs/ROADMAP/MULTILANG.md`](C:\repos\documentation.nvim\docs\ROADMAP) noch gar nicht erreicht. Ein Verweis dort auf insights.nvim würde verhindern, dass jemand diese Sprachunterstützung in documentation.nvim von Grund auf neu baut, obwohl sie – wenn auch schlanker – schon existiert.

---

## 4. Was bewusst **nicht** sinnvoll ist

In derselben Ehrlichkeits-Konvention, die die anderen beiden Repos für sich selbst anwenden ("Deliberately not", [IDEAS.md §7](C:\repos\runtime-analysis.nvim\docs\IDEAS.md):415-424):

- **Kein Merge/keine Übernahme von Modulen.** documentation.nvim's Wert liegt gerade in Enge + Determinismus (CI-Byte-Vergleich); insights.nvim's Wert liegt in Breite + Interaktivität. Eine Verschmelzung würde beides verwässern.
- **insights.nvim sollte nicht hart von den beiden anderen abhängen** — dieselbe Regel, die documentation.nvim sich selbst für runtime-analysis.nvim auferlegt (nie Hard-Dependency eines statischen/Ad-hoc-Analysetools auf ein optionales Laufzeit-Plugin).
- **`tree`, `fileinfo`, `compress`, `conflicts`, `unimported`, `devserver`** haben keine sinnvolle Berührung mit den anderen beiden — reine Editor-Workflow-Automatisierung, orthogonal zum Doku-/Runtime-Thema. Hier künstlich eine Verbindung zu suchen wäre Kraft in die falsche Richtung.

---

## Kurzfazit

insights.nvim ist kein fehlendes Puzzleteil des dokumentierten documentation.nvim/runtime-analysis.nvim-Ökosystems, sondern ein **drittes, orthogonales Werkzeug** mit echtem Alleinstellungsmerkmal (Polyglot, ad hoc, kein IR/CI-Anspruch). Der größte Sofort-Nutzen liegt nicht in tiefer Code-Integration, sondern darin, das explizit zu machen: READMEs verlinken (a) und die beiden konkreten Redundanz-Kandidaten (`imports unused`, Workspace-Symbole, Punkt 2) im jeweils anderen Backlog vermerken, bevor dort etwas doppelt gebaut wird. Danach lohnt sich am ehesten (b) Telemetrie-Selbstinstrumentierung — billig, nutzt existierende Infrastruktur, liefert echte Nutzungsdaten für insights.nvim's eigene Roadmap-Entscheidungen.

---

