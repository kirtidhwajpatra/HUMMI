import SwiftUI
import UIKit
import Combine

class RichTextContext: ObservableObject {
    @Published var isEmpty: Bool = true
    weak var textView: UITextView? {
        didSet {
            isEmpty = textView?.text.isEmpty ?? true
        }
    }
    
    func toggleBold() {
        guard let tv = textView else { return }
        let font = tv.typingAttributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: 17)
        let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
        
        var traits = font.fontDescriptor.symbolicTraits
        if isBold {
            traits.remove(.traitBold)
        } else {
            traits.insert(.traitBold)
        }
        
        if let newDescriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            let newFont = UIFont(descriptor: newDescriptor, size: font.pointSize)
            applyAttribute(.font, value: newFont)
        }
    }
    
    func changeColor(_ color: UIColor) {
        applyAttribute(.foregroundColor, value: color)
    }
    
    func changeFontSize(increase: Bool) {
        guard let tv = textView else { return }
        
        let range = tv.selectedRange.length > 0 ? tv.selectedRange : NSRange(location: 0, length: tv.textStorage.length)
        
        tv.textStorage.beginEditing()
        tv.textStorage.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            let font = value as? UIFont ?? UIFont.systemFont(ofSize: 17)
            let newSize = increase ? font.pointSize + 2 : max(10, font.pointSize - 2)
            let newFont = font.withSize(newSize)
            tv.textStorage.addAttribute(.font, value: newFont, range: r)
        }
        tv.textStorage.endEditing()
        
        if let font = tv.typingAttributes[.font] as? UIFont {
            let newSize = increase ? font.pointSize + 2 : max(10, font.pointSize - 2)
            tv.typingAttributes[.font] = font.withSize(newSize)
        }
        
        tv.delegate?.textViewDidChange?(tv)
    }
    
    private func applyAttribute(_ name: NSAttributedString.Key, value: Any) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        if range.length > 0 {
            tv.textStorage.beginEditing()
            tv.textStorage.addAttribute(name, value: value, range: range)
            tv.textStorage.endEditing()
            tv.delegate?.textViewDidChange?(tv)
        } else {
            tv.typingAttributes[name] = value
        }
    }
}

class PlainPasteTextView: UITextView {
    override func paste(_ sender: Any?) {
        let oldLength = textStorage.length
        let oldSelectedRange = selectedRange
        
        // Let UITextView handle HTML/RTF parsing so paragraphs and newlines 
        // from websites are correctly preserved.
        super.paste(sender)
        
        let newLength = textStorage.length
        let insertedLength = newLength - oldLength
        guard insertedLength > 0 else { return }
        
        let insertedRange = NSRange(location: oldSelectedRange.location, length: insertedLength)
        
        // Strip the pasted formatting (colors, fonts, backgrounds) 
        // and apply our current text style instead.
        textStorage.beginEditing()
        textStorage.setAttributes(typingAttributes, range: insertedRange)
        textStorage.endEditing()
        
        delegate?.textViewDidChange?(self)
    }
}

struct RichTextEditor: UIViewRepresentable {
    @Binding var rtfData: Data
    @Binding var isFocused: Bool
    @ObservedObject var context: RichTextContext
    
    func makeUIView(context: Context) -> PlainPasteTextView {
        let textView = PlainPasteTextView()
        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .clear
        textView.font = UIFont.systemFont(ofSize: 18)
        textView.textColor = UIColor.label
        
        if !rtfData.isEmpty, let attrStr = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            textView.attributedText = attrStr
        } else {
            textView.attributedText = NSAttributedString(string: "", attributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.label])
        }
        
        self.context.textView = textView
        
        return textView
    }
    
    func updateUIView(_ uiView: PlainPasteTextView, context: Context) {
        if self.isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !self.isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var saveWorkItem: DispatchWorkItem?
        
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.context.isEmpty = textView.text.isEmpty
            }
            saveWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self = self, let tv = textView else { return }
                if let data = try? tv.attributedText.data(from: NSRange(location: 0, length: tv.attributedText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                    self.parent.rtfData = data
                }
            }
            saveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
            saveWorkItem?.cancel()
            if let data = try? textView.attributedText.data(from: NSRange(location: 0, length: textView.attributedText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                parent.rtfData = data
            }
        }
        
        @objc func doneTapped() {
            parent.isFocused = false
        }
    }
}
