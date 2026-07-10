import SwiftUI
import UIKit
import Combine

class RichTextContext: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    weak var textView: UITextView?
    
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

struct RichTextEditor: UIViewRepresentable {
    @Binding var rtfData: Data
    var isFocused: FocusState<Bool>.Binding
    @ObservedObject var context: RichTextContext
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneBtn = UIBarButtonItem(title: "Done", style: .prominent, target: context.coordinator, action: #selector(Coordinator.doneTapped))
        toolbar.items = [flexSpace, doneBtn]
        textView.inputAccessoryView = toolbar
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if self.isFocused.wrappedValue && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !self.isFocused.wrappedValue && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            if let data = try? textView.attributedText.data(from: NSRange(location: 0, length: textView.attributedText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                parent.rtfData = data
            }
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused.wrappedValue {
                parent.isFocused.wrappedValue = true
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused.wrappedValue {
                parent.isFocused.wrappedValue = false
            }
        }
        
        @objc func doneTapped() {
            parent.isFocused.wrappedValue = false
        }
    }
}
