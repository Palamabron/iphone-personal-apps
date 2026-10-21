# Walidacja pierwszych IPA — 21.10.2026

Kod aplikacji: commit `66979d8d48449b4e0ae0ee1aef23026a59d5ad8e`. [Kompilacja i raporty](https://github.com/Palamabron/iphone-personal-apps/actions/runs/39633098802) zakończone sukcesem dla obu aplikacji. Kolejne zmiany dokumentacji nie modyfikują kodu tego wydania.

## Wykonane

- Standardowe publiczne runnery `macos-15`, Xcode 16.4, iPhoneOS SDK 18.5. Docelowy iOS 18.0+, ARM64, konfiguracja Release.
- 7 testów logiki Focus Tube i 20 testów logiki/kolektora Radaru na runnerach macOS.
- Poprawne zbudowanie obu aplikacji oraz rozszerzenia Safari. Brak danych Apple Account i profili podpisujących w kompilacji.
- Kontrola ZIP/Info.plist/Mach-O: pakiety dla iPhoneOS i ARM64, zgodne identyfikatory oraz wersje, ikony, kod i zasoby aplikacji. Focus zawiera rozszerzenie Safari, manifest ograniczony do YouTube, polski ekran konfiguracji i link zmiany konta. Radar zawiera samowystarczalny HTML z mostem natywnym.
- Kontrolę paczek powtórzono po pobraniu z GitHub Actions na Windowsa. Sumy SHA-256 są zgodne z raportami CI.
- Wcześniejsza próba interfejsu Radaru w Chromium z zastąpionym mostem: zapis i ponowne otwarcie, eksport ICS/JSON, import publicznego źródła, odrzucenie obcych adresów, zachowanie zapisów po awarii źródeł. To nie jest test Swift ani mobilnego Safari.

| Plik | Bajty | SHA-256 |
|---|---:|---|
| FocusTube-unsigned.ipa | 103739 | `69ecf062f76e353e36e5a7654e0b0822d161e5961c61eea3fb67b0461eb9af9b` |
| TechRadar-unsigned.ipa | 108357 | `e178e41bcb4814f417effedda17060f5c3bc0e3a779f7ffe2de0f96c3bad4f68` |

## Niewykonane

Nie uruchomiono symulatora ani fizycznego iPhone'a. Do sprawdzenia: podpisanie SideStore i Personal Team (w tym rozszerzenie), uruchomienie i widoczność w Safari, rzeczywisty zapis/odtworzenie, udostępnianie i import plików, dostęp do źródeł z sieci telefonu, odnowienie bez utraty danych. Działanie konta YouTube/Premium, audio w tle i PiP nie zostało potwierdzone.

## Ostrzeżenia narzędzi

Generator rozszerzenia z Xcode 16.4 zgłasza klucz `content_scripts.world`. Pozostawiono `MAIN` i minimalny iOS 18. [Dane zgodności MDN](https://github.com/mdn/browser-compat-data/blob/main/webextensions/manifest/content_scripts.json) wskazują obsługę tego klucza od Safari 18. Samo zestawienie tych informacji nie jest testem Safari na telefonie. Runtime ma również obserwację DOM i okresowe sprawdzanie adresu; nie opiera całej nawigacji wyłącznie na podmianie metod historii.

Pozostały komunikaty pomijania metadanych AppIntents (aplikacje nie implementują App Intents) oraz komunikaty GitHub Actions o środowisku Node.js użytym przez akcje. Nie ma ostrzeżeń o brakujących ikonach ani błędów kompilacji.
