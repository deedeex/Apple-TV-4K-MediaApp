//
//  FocusRestorationDisabler.swift
//  MediaApp
//
//  Wstawiany jako niewidoczny .background() w widoku otwieranym przez
//  fullScreenCover (MediaPagerView/AllMediaPagerView) — wyłącza natywne,
//  SYSTEMOWE (UIKit, nie SwiftUI) przywracanie fokusu na element, który miał
//  go PRZED prezentacją modala, po jego zamknięciu.
//
//  Bez tego: powrót z pełnoekranowego podglądu (Menu na pilocie) po
//  przewinięciu w nim kilku pozycji zostawiał fokus w siatce z powrotem na
//  kaflu, w który kliknięto PIERWOTNIE — nie na ostatnio oglądanej pozycji.
//  Wypróbowane wcześniej (i nieskuteczne) podejścia czysto w SwiftUI:
//  jednorazowe @FocusState, wielokrotne opóźnione @FocusState, oraz
//  .prefersDefaultFocus — wszystkie dawały TEN SAM objaw: fokus poprawny
//  przez chwilę, po czym system nadpisywał go z powrotem z opóźnieniem
//  rzędu pół sekundy. To, że nawet .prefersDefaultFocus (jedyny mechanizm
//  SwiftUI faktycznie UCZESTNICZĄCY w ustalaniu fokusu, nie tylko czytający
//  go po fakcie) nie pomógł, wskazuje, że system nie "ustala domyślny
//  fokus" w tym momencie — on AKTYWNIE PRZYWRACA konkretny, zapamiętany
//  wcześniej UIFocusItem, co jest mechanizmem UIKit, silniejszym niż
//  cokolwiek wystawionym w SwiftUI.
//
//  restoresFocusAfterTransition musi być ustawione na PREZENTOWANYM modalnie
//  UIViewController (tym z presentingViewController != nil) — czyli
//  UIHostingController hostującym CAŁĄ zawartość tego fullScreenCover, NIE
//  na tym niewidocznym pomocniczym kontrolerze samym w sobie. Stąd
//  wędrówka w górę po .parent, zamiast ustawiania właściwości na sobie.
//

import SwiftUI
import UIKit

struct FocusRestorationDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        DisablingViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class DisablingViewController: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            disableRestorationOnPresentedAncestor()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Druga próba — na wypadek, gdyby przy didMove(toParent:)
            // hierarchia (parent) nie była jeszcze w pełni ustawiona.
            disableRestorationOnPresentedAncestor()
        }

        private func disableRestorationOnPresentedAncestor() {
            var current: UIViewController? = self
            while let vc = current {
                if vc.presentingViewController != nil {
                    vc.restoresFocusAfterTransition = false
                    return
                }
                current = vc.parent
            }
        }
    }
}
