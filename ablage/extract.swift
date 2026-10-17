// Text from PDFs (OCR for scanned pages) and images (Vision OCR), used by ablage.py.
// Built by install.sh: swiftc -O extract.swift -o ~/.config/ablage/extract
import Foundation
import PDFKit
import Vision
import AppKit

// usage: extract <outdir> <file>...   writes <outdir>/<basename>.txt (first 3 pages, max 8000 chars)
func ocr(_ img: CGImage) -> String {
    let req = VNRecognizeTextRequest()
    req.recognitionLanguages = ["de-DE", "en-US"]
    req.recognitionLevel = .accurate
    try? VNImageRequestHandler(cgImage: img).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}
func render(_ page: PDFPage) -> CGImage? {
    let b = page.bounds(for: .mediaBox); let s: CGFloat = 2
    let img = page.thumbnail(of: NSSize(width: b.width*s, height: b.height*s), for: .mediaBox)
    return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
}
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
for path in args.dropFirst(2) {
    let url = URL(fileURLWithPath: path)
    var text = ""
    let ext = url.pathExtension.lowercased()
    if ext == "pdf", let doc = PDFDocument(url: url) {
        for i in 0..<min(3, doc.pageCount) {
            guard let p = doc.page(at: i) else { continue }
            var t = p.string ?? ""
            if t.trimmingCharacters(in: .whitespacesAndNewlines).count < 40, let img = render(p) { t = "[OCR]\n" + ocr(img) }
            text += t + "\n---page---\n"
        }
    } else if ["png","jpg","jpeg","heic","tif","tiff"].contains(ext), let img = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        text = "[OCR]\n" + ocr(img)
    }
    let dst = out.appendingPathComponent(url.lastPathComponent + ".txt")
    try? String(text.prefix(8000)).write(to: dst, atomically: true, encoding: .utf8)
}
