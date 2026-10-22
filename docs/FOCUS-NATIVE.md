# Focus Tube Native 0.2.0

Samodzielna aplikacja, odrębna od rozszerzenia Safari 0.1.1. Identyfikator `dev.palamabron.focustube.native`. Natynwy ekran startowy SwiftUI, wyszukiwarka, zapis do 100 linków lokalnie, powrót, odświeżanie, subskrypcje i wybór konta. Wyniki i oficjalny odtwarzacz YouTube działają w WKWebView wewnątrz aplikacji, bez przechodzenia do Safari. To nie jest w pełni natywny klon wszystkich ekranów YouTube.

Wbudowany filtr ukrywa rozpoznane Shortsy i rekomendacje, porcjuje wyniki po 15 oraz ogranicza autoplay. Filtr działa również przy zmianie adresu bez przeładowania. Nie ma przełącznika wyłączającego filtrowanie. Widok YouTube pozostaje zasłonięty, jeżeli filtr nie potwierdzi aktywacji. Osobna kontrola natywna blokuje nawigację do Shorts oraz obcych hostów; dopuszcza YouTube i konkretne hosty logowania/zgód Google. Treści osadzonych ramek i media obsługuje WebKit. Nie stosujemy podmiany User-Agent, ekstrakcji strumieni ani kopiowania sesji Safari. Cookies w domyślnym magazynie WebKit zachowują sesję między uruchomieniami.

## Instalacja

Pobierz **FocusTubeNative-unsigned.ipa** z wydania `focus-native-0.2.0`, następnie otwórz SideStore → My Apps → + i wybierz pobrany plik. Samo pobranie pliku nie instaluje aplikacji. Wpisuj dane Apple wyłącznie w narzędziu instalacyjnym. Szczegóły konfiguracji SideStore dla Windows/Ubuntu: [INSTALL_IPHONE.md](INSTALL_IPHONE.md).

Starszy Focus Tube z rozszerzeniem Safari jest osobną aplikacją. Przy limicie trzech aplikacji (SideStore również zajmuje miejsce) zdezaktywuj stare rozszerzenie, zanim zainstalujesz wersję Native razem z Tech Radarem. Nie musisz usuwać Userscripts z App Store.

## Pierwsza próba

1. Otwórz aplikację i wyszukaj długi film. Rozpocznij odtwarzanie ręcznie.
2. Zapisz film ikoną zakładki, wróć ikoną domu, otwórz zapis i sprawdź go po ponownym uruchomieniu.
3. Wejdź w Konto. Sprawdź logowanie na konto z Premium i ponowne uruchomienie bez utraty sesji. Google może odmówić logowania w osadzonej przeglądarce; aplikacja tego nie obchodzi.
4. Sprawdź brak Shorts, świadome ładowanie kolejnych 15 wyników oraz brak samoczynnego przejścia do następnego filmu.
5. Osobno sprawdź pełny ekran, Premium, PiP i blokadę ekranu. Nie są jeszcze potwierdzone. Pobieranie offline nie jest dostępne.

Nie blokuje oficjalnej aplikacji YouTube, usuwania aplikacji ani ustawień telefonu. Nie wszystkie filmy Shorts rozpoznajemy, jeśli są udostępnione jako zwykły adres `/watch`.

## Odtworzenie kompilacji

Workflow **Build Focus Tube Native** w publicznym repozytorium uruchamia testy URL w Swift i testy filtra, kompiluje IPA dla iPhoneOS/ARM64 i osobno aplikację symulatora. Bez kont Apple i bez płatnego runnera. Lokalnie na macOS: `node scripts/build-native-ios.mjs`. Windows pozwala rozwijać kod i instalować gotową paczkę; nie kompiluje iOS.

Aktualne wyniki prób są w [BUILD-VALIDATION.md](BUILD-VALIDATION.md). Zrzut symulatora nie potwierdza logowania ani Premium na urządzeniu.
