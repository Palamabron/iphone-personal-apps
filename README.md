# Osobiste aplikacje iPhone

Dwa projekty aplikacji na iOS 18 lub nowszy, instalowane bez płatnego konta Apple Developer. Windows lub Ubuntu wystarcza do instalacji przez SideStore. Źródła wybrane za zgodą właściciela; pierwotne repozytoria pozostają prywatne. W repozytorium nie ma konfiguracji prywatnego hostingu, kont, certyfikatów ani danych preferencji. Dołączone wydarzenia pochodzą z publicznych ogłoszeń.

| Aplikacja | Co robi | Pobierz |
|---|---|---|
| Focus Tube Native 0.2.0 | Samodzielna aplikacja z natywnym ekranem, wbudowanym YouTube i filtrem Shorts | [Pobierz i zainstaluj](docs/FOCUS-NATIVE.md) |
| Focus Tube 0.1.1 | Własne rozszerzenie Safari filtrujące YouTube, polski ekran konfiguracji | [FocusTube-unsigned.ipa](https://github.com/Palamabron/iphone-personal-apps/releases/download/iphone-2026.10.21/FocusTube-unsigned.ipa) |
| Tech Radar 0.2.0 | Samodzielna aplikacja z wydarzeniami, lokalnym zapisem i odświeżaniem publicznych źródeł | [TechRadar-unsigned.ipa](https://github.com/Palamabron/iphone-personal-apps/releases/download/iphone-2026.10.21/TechRadar-unsigned.ipa) |

**[Instrukcja instalacji na iPhonie z Windowsa/Ubuntu](docs/INSTALL_IPHONE.md).** Pobrane IPA trzeba podpisać przy instalacji przez SideStore. Samo pobranie pliku w Safari nie instaluje aplikacji. Darmowy podpis wymaga odnawiania przed upływem 7 dni.

Obie kompilacje Xcode oraz kontrole paczek urządzenia przeszły: [wynik GitHub Actions](https://github.com/Palamabron/iphone-personal-apps/actions/runs/39633098802), [zakres walidacji](docs/BUILD-VALIDATION.md). **Instalacja, podpisanie i działanie na fizycznym iPhonie pozostają do potwierdzenia.**

W GitHub Actions można ręcznie uruchomić Build personal iPhone apps. Workflow używa standardowego macos-15, nie potrzebuje konta Apple i pomija prywatne repozytoria, by nie zużywać płatnych minut. Artefakty Actions są dostępne przez jeden dzień; pliki wydania mają stałe linki powyżej. [Zasady bezpłatnego użycia GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Kompilacja lokalna na własnym Macu z Xcode: przejść do `apps/<nazwa>` i uruchomić `node scripts/build-ios.mjs`. Testy wspólnej logiki: `node --test` w danym katalogu aplikacji. Ikony odtwarza `node scripts/create-icons.mjs`. Manifest źródeł odświeża `node scripts/update-source-manifest.mjs`.


Focus Tube Native jest osobnym przyrostem z 22.10.2026; wyniki starszej kompilacji rozszerzenia nie stanowią testu nowej aplikacji. Zobacz [zakres i instalację](docs/FOCUS-NATIVE.md).
