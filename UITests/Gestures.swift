import XCTest

/// Проверка свайпов настоящими касаниями в симуляторе (облачная сборка пишет экран на видео).
/// Запуск: .github/workflows/gestures.yml — вручную или отправкой в ветку swipe.
final class Gestures: XCTestCase {
    private var app: XCUIApplication!

    private func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }
    private func drag(_ x: CGFloat, _ y: CGFloat, dx: CGFloat, dy: CGFloat = 0, speed: CGFloat = 450, hold: TimeInterval = 0) {
        at(x, y).press(forDuration: 0.05, thenDragTo: at(x + dx, y + dy), withVelocity: XCUIGestureVelocity(rawValue: speed), thenHoldForDuration: hold)
    }
    /// Рамки реплик, которые сейчас целиком видны между верхней панелью и нижними кнопками (сверху вниз).
    private func bubbles() -> [CGRect] {
        let h = app.frame.height
        let q = app.otherElements.matching(identifier: "bubble")
        return (0..<q.count).map { q.element(boundBy: $0).frame }.filter { $0.minY > 110 && $0.maxY < h - 250 }.sorted { $0.minY < $1.minY }
    }
    private func step(_ name: String) { print("STEP \(name) \(Date().timeIntervalSince1970)") }

    private func big(_ w: CGFloat, _ h: CGFloat) {
        drag(w / 2, h * 0.5, dx: 0, dy: -260, speed: 500)
        let flip = app.buttons["Перевернуть"]
        if !flip.waitForExistence(timeout: 2) { XCTFail("не открылось крупно"); return }
        sleep(1)
        drag(w / 2, h * 0.4, dx: 0, dy: 220, speed: 600); sleep(2)
        if flip.exists { XCTFail("не закрылось смахиванием вниз"); app.buttons.element(boundBy: app.buttons.count - 1).tap(); sleep(1) }
    }

    func testSwipes() {
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "com.pavliq55.tapny")
        app.launchArguments = ["-demoMany", "YES", "-consent_v1", "YES", "-dbgPull", "YES"]
        app.launch()
        sleep(3)
        let w = app.frame.width, h = app.frame.height
        var b = bubbles()
        print("BUBBLES \(b)")
        guard let last = b.last else { XCTFail("нет реплик"); return }

        step("1 чуть влево и отпустить — должна вернуться")
        drag(last.midX, last.midY - 20, dx: -60, speed: 200); sleep(1)

        step("2 вправо — озвучить: реплика сразу едет на место, кнопка «Готовлю…» → «Стоп» → «Озвучить»")
        drag(last.midX - 40, last.midY - 20, dx: 150, speed: 300); sleep(5)

        step("2б потянуть ленту вверх за край и отпустить — перевод на весь экран; смахнуть вниз — закрыть")
        big(w, h)

        step("3 прокрутка вниз-вверх по репликам с боковым уводом — реплики не должны ехать вбок")
        drag(w / 2, h * 0.45, dx: 25, dy: 260, speed: 500); sleep(1)
        drag(w / 2, h * 0.3, dx: -25, dy: 200, speed: 500); sleep(1)
        drag(w / 2, h * 0.6, dx: 20, dy: -400, speed: 700); sleep(1)
        drag(w / 2, h * 0.6, dx: 0, dy: -70, speed: 700); sleep(2)
        if app.buttons["Перевернуть"].exists {   // обычная прокрутка к концу не должна открывать перевод крупно
            XCTFail("открылось крупно при обычной прокрутке"); drag(w / 2, h * 0.4, dx: 0, dy: 220, speed: 600); sleep(2)
        }

        step("4 удалить крупную")
        b = bubbles(); if let r = b.last { drag(r.midX + 40, r.midY - 20, dx: -170, speed: 500) }; sleep(2)

        step("5 вернуть")
        let undo = app.buttons["Удалено · Вернуть"]
        if undo.waitForExistence(timeout: 2) { undo.tap() } else { XCTFail("нет кнопки возврата") }
        sleep(2)

        step("6 удалить крупную и сразу следующую")
        b = bubbles(); if let r = b.last { drag(r.midX + 40, r.midY - 20, dx: -170, speed: 500) }; sleep(1)
        b = bubbles(); if let r = b.last { drag(r.midX + 40, r.midY, dx: -170, speed: 500) }; sleep(7)

        step("7 удалить из середины")
        b = bubbles(); if b.count > 2 { let r = b[b.count - 3]; drag(r.midX + 40, r.midY, dx: -170, speed: 500) }; sleep(2)

        step("8 прокрутить к старым и удалить там")
        drag(w / 2, h * 0.35, dx: 0, dy: 300, speed: 600); sleep(1)
        b = bubbles(); if b.count > 1 { let r = b[1]; drag(r.midX + 40, r.midY, dx: -170, speed: 500) }; sleep(3)

        step("9 быстрый короткий смах")
        b = bubbles(); if let r = b.last { drag(r.midX + 30, r.midY, dx: -70, speed: 2200) }; sleep(2)

        step("10 медленно вбок с уводом вниз, подержать, отпустить")
        b = bubbles(); if let r = b.last { drag(r.midX + 40, r.midY, dx: -140, dy: 45, speed: 160, hold: 0.6) }; sleep(3)

        step("11 вправо на обычной реплике")
        b = bubbles(); if let r = b.first { drag(r.midX - 40, r.midY, dx: 160, speed: 300) }; sleep(2)
        step("12 то же в короткой ленте: потянуть вверх — крупно, вниз — закрыть")
        big(w, h)
        step("13 как вживую: слова сразу пишутся в облаке, готовый перевод — в нём же")
        app.terminate()
        app.launchArguments = ["-demoFlow", "YES", "-consent_v1", "YES"]
        app.launch(); sleep(25)
        step("14 настройки: открыть, пролистать до конца, закрыть")
        app.terminate()
        app.launchArguments = ["-demoMany", "YES", "-consent_v1", "YES"]
        app.launch(); sleep(3)
        let set = app.buttons["Настройки"]
        if set.waitForExistence(timeout: 3) {
            set.tap(); sleep(2)
            drag(w / 2, h * 0.7, dx: 0, dy: -420, speed: 600); sleep(1)
            drag(w / 2, h * 0.7, dx: 0, dy: -420, speed: 600); sleep(2)
            let done = app.buttons["Готово"]
            if done.exists { done.tap() } else { XCTFail("нет «Готово»") }
            sleep(1)
        } else { XCTFail("нет кнопки настроек") }
        step("15 коснуться обычной реплики — под ней кнопки; озвучить оттуда; коснуться ещё раз — кнопки убрались")
        b = bubbles()
        if b.count > 2 {
            let r = b[b.count - 3]
            at(r.midX, r.midY).tap(); sleep(2)
            let say = app.buttons.matching(identifier: "Озвучить")
            if say.count < 2 { XCTFail("кнопки под обычной репликой не появились: \(say.count)") } else { say.element(boundBy: 0).tap(); sleep(4) }
            b = bubbles()
            if b.count > 2 { let r2 = b[b.count - 3]; at(r2.midX, r2.minY + 24).tap(); sleep(2) }
            if app.buttons.matching(identifier: "Озвучить").count != 1 { XCTFail("кнопки не убрались") }
        }
        step("16 написать текстом: слова набираются прямо в облаке, перевод встаёт в него же")
        let kb = app.buttons["Написать текстом"]
        if kb.waitForExistence(timeout: 2) {
            kb.tap(); sleep(2)
            app.typeText("Можно оплатить картой?"); sleep(2)
            let go = app.buttons["Перевести"]
            if go.exists { go.tap() } else { XCTFail("нет «Перевести»") }
            sleep(5)
        } else { XCTFail("нет кнопки «Написать текстом»") }
        step("конец")
    }
}
