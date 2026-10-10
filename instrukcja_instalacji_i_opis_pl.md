# Pingu Player – Odtwarzacz mediów dla Apple TV (tvOS)

**Pingu Player** to dedykowana aplikacja na Apple TV (tvOS) do bezpośredniego przeglądania zdjęć oraz odtwarzania filmów przechowywanych na domowym serwerze NAS (np. Synology) z wykorzystaniem protokołu SMB. 

Aplikacja działa bezpośrednio na plikach udostępnionych w sieci lokalnej – bez konieczności korzystania z usługi iCloud oraz bez wymogu importowania czegokolwiek do systemowej biblioteki Zdjęć.

---

## 🌟 Możliwości i funkcje aplikacji

### 🎨 Interfejs, Siatka Kafelków i Design (UI/UX)
* **Nowoczesny wygląd Liquid Glass:** Elementy interfejsu wykorzystują natywne efekty przezroczystości i rozmycia szkła (*Liquid Glass / Materials*), zapewniając spójność z najnowszym systemem tvOS.
* **Siatka kafelków (Grid View):** Multimedia wyświetlane są w przejrzystej siatce kafelków, zoptymalizowanej pod kątem szybkiego przeglądania dużych zbiorów.
* **Natywna obsługa pilota Siri Remote:** Płynna nawigacja po kafelkach i menu przy użyciu zarówno gestów (swipe/touchpad), jak i tradycyjnych kliknięć.
* **Cztery główne zakładki:** *Wszystko*, *Zdjęcia*, *Wideo* oraz *Ustawienia*.

### 🗂️ Nawigacja i Boczny Panel Osi Czasu
* **Dedykowany lewy panel (Oś czasu):** Po lewej stronie ekranu znajduje się wygodna kolumna z podziałem na lata i miesiące.
* **Szybki skok do okresu:** Wybór konkretnego miesiąca z lewej kolumny natychmiast przewija siatkę multimediów do wskazanego przedziału czasowego.

### 🎬 Odtwarzanie i podgląd na pełnym ekranie
* **Chronologiczne przeglądanie:** Płynne przechodzenie pilotem między zdjęciami, materiałami Live Photo oraz plikami wideo.
* **Obsługa Live Photo:** Odtwarzanie animacji poprzez jedno kliknięcie środkowego przycisku pilota.
* **Odtwarzanie Wideo (w tym 4K HDR):** Błyskawiczny start (ok. 1 sekundy) dzięki strumieniowaniu na żywo z serwera NAS zamiast pobierania całego pliku na urządzenie.
* **Wygodne sterowanie po seansie:** Po zakończeniu odtwarzania wideo pojawiają się przyciski *„Poprzednie”*, *„Odtwórz ponownie”* oraz *„Następne”*.

### ⚡ Wydajność i dwupoziomowy Cache (100k+ plików)
* **Natychmiastowy start:** Aplikacja po uruchomieniu od razu wyświetla zapamiętaną listę plików, a synchronizację i odświeżanie wykonuje w tle.
* **Zaawansowany dwupoziomowy cache (RAM + Dysk):** Zarówno miniatury, jak i przygotowane pliki multimedialne korzystają z dwupoziomowej pamięci podręcznej (szybka pamięć RAM oraz lokalny dysk Apple TV). Zapobiega to ponownemu pobieraniu tych samych danych z serwera NAS i zapewnia płynne przeglądanie nawet przy ponad 100 000 plików.
* **Pre-loading (wyprzedzające ładowanie):** Sąsiednie zdjęcia i multimedia są przygotowywane w tle, zapewniając błyskawiczne otwieranie przy przełączaniu.

### ⚙️ Konfiguracja i Zarządzanie (Ustawienia)
* **Podgląd i obsługa serwera:** Możliwość podglądu danych połączonego serwera NAS, ręcznego odświeżenia biblioteki oraz usunięcia pamięci podręcznej (czyszczenie cache).
* **Pełna konfiguracja połączenia:** Edycja hosta, nazwy udziału (share), danych użytkownika oraz ścieżki do folderu ze zdjęciami.
* **Personalizacja:** Wybór języka interfejsu (polski, angielski) oraz zmiana tła aplikacji.

---

## 🚀 Instrukcja instalacji i uruchomienia

### Wymagania wstępne
* Komputer Mac z zainstalowanym programem **Xcode 15** (lub nowszym).
* Apple TV 4K z systemem **tvOS 17** (lub nowszym) połączony z tą samą siecią lokalną co serwer NAS.

### Krok po kroku
1. Sklonuj repozytorium na swój komputer:
   ```bash
   git clone https://github.com/deedeex/Apple-TV-4K-MediaApp.git
   ```
2. Otwórz projekt w Xcode, klikając plik `MediaApp.xcodeproj`.
3. Podłącz Apple TV jako urządzenie docelowe w Xcode (lub wybierz symulator tvOS).
4. Zbuduj i uruchom projekt (`⌘ + R`).
5. W zakładce **Ustawienia** wprowadź dane dostępowe do swojego serwera NAS (SMB).