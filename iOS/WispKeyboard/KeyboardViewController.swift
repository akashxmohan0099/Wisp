import UIKit

final class KeyboardViewController: UIInputViewController {
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }

    private func setupView() {
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let dictate = makeButton(title: "Dictate", image: "textformat", action: #selector(startDictate))
        let compose = makeButton(title: "Compose", image: "sparkles", action: #selector(startCompose))
        let insert = makeButton(title: "Insert", image: "text.insert", action: #selector(insertLatest))
        let next = makeButton(title: "Next", image: "globe", action: #selector(nextKeyboard))

        [dictate, compose, insert, next].forEach(stack.addArrangedSubview)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }

    private func makeButton(title: String, image: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: image)
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.baseBackgroundColor = title == "Compose" ? .systemPurple : .systemGreen
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .medium

        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func startDictate() {
        openApp(mode: .dictate)
    }

    @objc private func startCompose() {
        openApp(mode: .compose)
    }

    @objc private func insertLatest() {
        let text = SharedStore.latestText()
        guard !text.isEmpty else {
            return
        }

        textDocumentProxy.insertText(text)
    }

    @objc private func nextKeyboard() {
        advanceToNextInputMode()
    }

    private func openApp(mode: WispMode) {
        SharedStore.savePendingMode(mode)

        var components = URLComponents()
        components.scheme = "wisp"
        components.host = "record"
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode.rawValue)
        ]

        guard let url = components.url else {
            return
        }

        extensionContext?.open(url)
    }
}
