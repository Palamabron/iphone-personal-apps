# Instalacja na własnym iPhonie

Wymagany iOS 18 lub nowszy, własny Apple Account, Wi-Fi i kabel USB do pierwszej instalacji SideStore. Windows lub Ubuntu wystarcza; prywatny Mac i płatne konto Apple Developer nie są potrzebne. Pliki IPA są niepodpisane — SideStore podpisze je Twoim kontem przy instalacji.

## 1. Przygotuj SideStore

Postępuj według aktualnych oficjalnych instrukcji: [przygotowanie Windowsa/Ubuntu](https://docs.sidestore.io/docs/installation/prerequisites), następnie [instalacja SideStore](https://docs.sidestore.io/docs/installation/install).

Na Windowsie obejmuje to instalację iTunes lub obsługiwanych sterowników Apple oraz programu iloader. Na Ubuntu potrzebny jest usbmuxd i iloader. Na iPhonie zainstaluj LocalDevVPN z App Store. Podłącz telefon przez USB, zaakceptuj zaufanie do komputera i w iloader wybierz instalację stabilnego SideStore.

Na telefonie zaufaj własnemu profilowi w Ustawienia → Ogólne → VPN i zarządzanie urządzeniami. Włącz Ustawienia → Prywatność i ochrona → Tryb dewelopera i wykonaj wymagany restart. Połącz LocalDevVPN, otwórz SideStore i najpierw odśwież sam SideStore, klikając jego licznik dni w My Apps. Dokładne komunikaty zależą od wersji iOS.

## 2. Pobierz i zainstaluj aplikacje

Pobierz pliki `FocusTube-unsigned.ipa` oraz `TechRadar-unsigned.ipa` z [najnowszego wydania](https://github.com/Palamabron/iphone-personal-apps/releases/latest), najlepiej bezpośrednio w Safari na iPhonie. Zostaną zapisane w Plikach, zwykle w Pobranych.

W SideStore otwórz My Apps, wybierz dodawanie aplikacji przyciskiem „+” i wskaż pobrany plik `.ipa`. Powtórz dla drugiej aplikacji. Podczas instalacji/odnawiania wymagane jest Wi-Fi i połączony LocalDevVPN. Nazwy konta i hasło wpisuj w narzędziach instalacyjnych, nigdy w repozytorium lub na stronie aplikacji.

Pierwsza instalacja na rzeczywistym iPhonie pozostaje do potwierdzenia. Powodzenie kompilacji oraz kontroli pliku nie potwierdza podpisania go na konkretnym koncie Apple.

## 3. Uruchom Radar

Otwórz Tech Radar z ekranu telefonu. Wydarzenia i zapisane wybory są wewnątrz tej aplikacji; nie musisz logować się do hostingu strony. Przycisk „Odśwież źródła” czyta publiczne strony z sieci telefonu. Jeśli źródło ogranicza odczyt, zobaczysz raport, a wcześniejsze dane pozostaną dostępne. Facebook i LinkedIn nadal wymagają ręcznego dodawania.

Aby przenieść zapisane wybory z wersji webowej: w poprzednim Radarze rozwiń „Twoje zainteresowania i dane”, wybierz „Eksportuj moje dane”, a w nowej aplikacji „Przywróć kopię” i wskaż JSON. Nie usuwaj poprzedniej kopii przed sprawdzeniem importu.

## 4. Włącz Focus Tube w Safari

Otwórz Focus Tube i przejdź instrukcję. W Ustawienia → Aplikacje → Safari → Rozszerzenia włącz Focus Tube i zezwól na dostęp do YouTube. Jeśli masz działający skrypt Focus Tube w Userscripts, pozostaw aktywną tylko jedną kopię filtra.

W zwykłej karcie Safari wpisz `m.youtube.com`. Zielona wyszukiwarka albo napis „filtr aktywny” potwierdzi działanie. Zmiana konta jest pod „Zmień konto”. Konto YouTube pozostaje w Safari; oficjalna aplikacja YouTube jest poza zakresem filtra. Premium, odtwarzanie w tle i PiP wymagają sprawdzenia na telefonie.

## Odnawianie

Darmowe podpisanie wygasa po 7 dniach. Przed upływem terminu otwórz SideStore na Wi-Fi, połącz LocalDevVPN i odśwież aplikacje. Nie polegaj wyłącznie na odświeżaniu w tle. Nie usuwaj aplikacji przy zwykłym odnawianiu; Radar pozwala dodatkowo wyeksportować dane.

Standardowy limit to trzy aktywne aplikacje podpisane darmowym kontem, wliczając SideStore. SideStore, Focus Tube i Tech Radar zajmują te trzy miejsca. Rozszerzenie Safari zużywa również osobny App ID. [Limity i odnawianie SideStore](https://docs.sidestore.io/docs/faq).
