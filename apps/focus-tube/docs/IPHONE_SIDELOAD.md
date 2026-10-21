# iPhone bez prywatnego Maca

Stan: 21.10.2026. Kompilacja Xcode aplikacji i rozszerzenia oraz kontrola pakietu IPA przeszły. [Pobierz plik i instrukcję](https://github.com/Palamabron/iphone-personal-apps). Podpisanie SideStore, symulator i fizyczny iPhone pozostają do sprawdzenia. Oryginalne repozytorium zachowano prywatne; wybrane źródła opublikowano za zgodą właściciela w osobnym repozytorium.

## Wybrany wariant Focus Tube

Własna aplikacja iOS zawierająca rozszerzenie Safari, zbudowana z tego samego filtra co Userscripts. Instalacja IPA zastępuje instalowanie menedżera Userscripts i ręczne przenoszenie pliku JavaScript. Oglądanie nadal odbywa się w Safari, dzięki czemu pozostaje w tej samej sesji konta YouTube. Nie jest to własny odtwarzacz wewnątrz aplikacji ani nakładka na oficjalny YouTube.

Packager Xcode generuje kontener aplikacji oraz rozszerzenie. Gotowy pakiet ma polski ekran konfiguracji i ikony. Trzeba sprawdzić na telefonie podpisanie rozszerzenia przez SideStore, jego uruchomienie oraz działanie kontekstu MAIN w docelowej wersji Safari. Nie deklarujemy, że sama kompilacja potwierdzi działanie Premium. [Raport kompilacji i znane ostrzeżenie generatora](https://github.com/Palamabron/iphone-personal-apps/blob/main/docs/BUILD-VALIDATION.md).

## Kompilacja bez firmowego MacBooka

- `node scripts/build-ios.mjs` działa na macOS z Xcode. Tworzy projekt w nowym, lokalnym folderze `build/ios/`, kompiluje dla urządzenia i pakuje niepodpisane IPA.
- Workflow `iPhone IPA (zero paid runners)` korzysta ze standardowego `macos-15` w GitHub Actions i uruchamia się wyłącznie ręcznie.
- Dopóki repozytorium jest prywatne, zadanie jest celowo pomijane. Nie uruchomiono płatnych minut i nie zmieniono widoczności repozytorium.
- W publicznym repozytorium standardowe runnery są bezpłatne według bieżących zasad GitHuba. Zmiana widoczności wymaga decyzji użytkownika; można również przygotować osobne publiczne repozytorium z samymi oczyszczonymi źródłami kompilacji, bez historii.
- Alternatywa prywatna: własny runner macOS albo zweryfikowany bezpłatny limit Actions i twardy limit wydatków konta. Nie ustawiamy budżetów całego konta bez zgody.

Żadne Apple ID, hasło, certyfikat ani profil nie trafiają do GitHuba. Podpisanie odbywa się przy instalacji przez użytkownika.

## Instalacja gotowego IPA

1. Na własnym Windowsie lub Ubuntu zainstaluj SideStore zgodnie z jego oficjalną instrukcją, początkowo przez USB.
2. Na iPhonie włącz wymagany tryb dewelopera i zatwierdź własny profil. Aktualna instrukcja SideStore korzysta z LocalDevVPN i Wi-Fi.
3. Pobierz artefakt IPA z udanej kompilacji, rozpakuj ZIP artefaktu i zaimportuj `.ipa` w SideStore. Podpisanie wymaga Twojego Apple Account; nie podawaj hasła w tej rozmowie.
4. W ustawieniach Safari włącz rozszerzenie Focus Tube i nadaj dostęp do YouTube. Przed użyciem wyłącz starą kopię tego samego filtra w Userscripts, aby dwa filtry nie konkurowały.
5. Odnawiaj aplikację przed upływem 7 dni. Automatyczne odnawianie nie jest gwarancją. SideStore zajmuje jeden z trzech standardowych slotów aplikacji; Focus Tube i Radar zajęłyby pozostałe dwa. Rozszerzenie zużywa też własny App ID.

## Źródła

- Apple Personal Team: https://developer.apple.com/help/account/basics/about-your-developer-account
- Packager Safari: https://developer.apple.com/documentation/safariservices/packaging-a-web-extension-for-safari
- GitHub Actions i koszty: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Instalacja SideStore: https://docs.sidestore.io/docs/installation/install
- Wymagania: https://docs.sidestore.io/docs/installation/prerequisites
