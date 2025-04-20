import SwiftUI
import LaTeXSwiftUI

/// A SwiftUI view that renders markdown text with support for LaTeX formulas, code blocks, and collapsible sections.
public struct MarkupText: View {
    /// The markdown string to render
    public var string: String
    @State private var expandedState: Bool = true
    @State private var thinkText: String? = nil // 用来存储提取的推理过程文本
    @State private var remainingText: String? = nil // 剩余的文本部分
    
    /// Keyword to highlight in red throughout the text
    public var highlightKeyword: String = ""

    /// Creates a new MarkdownText view with the specified markdown string.
    /// - Parameters:
    ///   - string: The markdown string to render
    ///   - highlightKeyword: Optional keyword to highlight in red (default: "")
    public init(string: String, highlightKeyword: String = "") {
        self.string = string
        self.highlightKeyword = highlightKeyword
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1.处理 <think>... </think> 部分，保留其余部分
            if let thinkText = thinkText {
                DisclosureGroup(isExpanded: $expandedState) {
                    ScrollView {
                        Text(thinkText)
                            .foregroundColor(.gray)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: expandedState ? 150 : 0)
                } label: {
                    Text("推理过程")
                        .bold()
                }
            }

            // 继续处理剩余部分
            if let remainingText = remainingText {
                // 处理多行LaTeX和代码块
                let elements = parseCompleteMarkdown(remainingText)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(elements.indices, id: \.self) { elementIndex in
                        let element = elements[elementIndex]
                        switch element {
                        case .markdown(let text):
                            renderMarkdown(text)
                                .padding(.vertical, 2)
                        case .latex(let formula):
                            // 处理LaTeX公式，确保多行公式块正确渲染
                            if formula.starts(with: "$$") && formula.hasSuffix("$$") {
                                // 多行LaTeX公式块
                                LaTeX(formula)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .background(Color.gray.opacity(0.05))
                                    .cornerRadius(4)
                            } else {
                                // 行内LaTeX公式
                                LaTeX(formula)
                                    .padding(.vertical, 2)
                            }
                        case .highlight(let highlightedText):
                            Text(highlightedText)
                                .font(.system(.body, design: .monospaced))
                                .padding(5)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(5)
                        case .codeBlock(let code, let language):
                            VStack(alignment: .leading) {
                                if !language.isEmpty {
                                    Text(language)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.top, 4)
                                        .padding(.horizontal, 8)
                                }
                                Text(code)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            extractThinkText() // 提取推理过程
        }
        .onChange(of: string) { _ in
            extractThinkText()
        }
    }
    
    // 提取<think>
    private func extractThinkText() {
        // 使用正则表达式检查是否有 <think> 标签
        let thinkStartRegex = try? NSRegularExpression(pattern: #"<think>"#, options: [])
        let thinkEndRegex = try? NSRegularExpression(pattern: #"</think>"#, options: [])
        
        // 检查是否包含 <think>
        if let thinkStartMatch = thinkStartRegex?.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) {
            // 如果找到了 <think>，将所有文本作为 thinkText
            if let thinkEndMatch = thinkEndRegex?.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) {
                // 找到 <think> 和 </think>，提取其中的内容
                let thinkRange = NSRange(location: thinkStartMatch.range.location, length: thinkEndMatch.range.location + thinkEndMatch.range.length - thinkStartMatch.range.location)
                let thinkContent = (string as NSString).substring(with: thinkRange)
                self.thinkText = thinkContent.replacingOccurrences(of: "<think>", with: "")
                                            .replacingOccurrences(of: "</think>", with: "")
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 获取剩余部分文本
                let remainingText = string.replacingOccurrences(of: thinkContent, with: "")
                self.remainingText = remainingText
            } else {
                // 如果没有找到 </think>，就把剩余部分当做thinkText的一部分
                self.thinkText = string.replacingOccurrences(of: "<think>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                self.remainingText = ""
            }
        } else {
            // 如果没有 <think> 标签，将整个文本作为剩余文本
            self.remainingText = string
        }
    }
    
    // markdown和匹配标红
    func renderMarkdown(_ text: String) -> some View {
        // 处理横线转为项目符号（只处理行开头的"-"）
        let lines = text.components(separatedBy: "\n")
        let processedLines = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).starts(with: "- ") {
                // 保留前导空格
                let whitespacePrefix = line.prefix(while: { $0.isWhitespace })
                let contentAfterDash = line.dropFirst(whitespacePrefix.count + 2) // 跳过"- "
                return whitespacePrefix + "• " + contentAfterDash
            }
            return line
        }
        let processedText = processedLines.joined(separator: "\n")
        
        guard var attributedString = try? AttributedString(
            markdown: processedText,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full, // 使用完整的Markdown语法解析
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return Text("")
        }

        // 关键词高亮
        if !highlightKeyword.isEmpty {
            let plainText = String(attributedString.characters)
            var searchRange = plainText.startIndex..<plainText.endIndex

            while let range = plainText.range(of: highlightKeyword, options: [], range: searchRange) {
                if let attrStart = AttributedString.Index(range.lowerBound, within: attributedString),
                   let attrEnd = AttributedString.Index(range.upperBound, within: attributedString) {
                    attributedString[attrStart..<attrEnd].foregroundColor = .red
                }

                searchRange = range.upperBound..<plainText.endIndex
            }
        }

        return Text(attributedString)
    }

    // 元素类型
    enum MarkdownElement {
        case markdown(String)
        case latex(String)
        case highlight(String)
        case codeBlock(String, String) // 代码块内容和语言
    }

    // 完整解析文本，支持多行元素
    private func parseCompleteMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let fullText = text
        
        do {
            // 用于存储需要排除的区域范围（已处理的代码块和LaTeX块）
            var excludedRanges: [NSRange] = []
            
            // 1. 首先匹配代码块 ```language ... ```（优先级最高）
            let codeBlockRegex = try NSRegularExpression(pattern: "```([a-zA-Z0-9]*)([\\s\\S]*?)```", options: [])
            let codeMatches = codeBlockRegex.matches(in: fullText, options: [], range: NSRange(fullText.startIndex..., in: fullText))
            
            // 代码块匹配
            var allMatches: [(NSRange, MarkdownElement)] = []
            
            // 先处理代码块（优先级最高）
            for match in codeMatches {
                let range = match.range
                let languageRange = match.range(at: 1)
                let codeRange = match.range(at: 2)
                
                let language = (fullText as NSString).substring(with: languageRange).trimmingCharacters(in: .whitespacesAndNewlines)
                let code = (fullText as NSString).substring(with: codeRange).trimmingCharacters(in: .whitespacesAndNewlines)
                
                allMatches.append((range, .codeBlock(code, language)))
                excludedRanges.append(range)
            }
            
            // 2. 匹配多行LaTeX
            let multiLineLatexRegex = try NSRegularExpression(pattern: "\\$\\$((?:[^$]|\\$(?!\\$))+?)\\$\\$", options: [])
            var latexMatches = multiLineLatexRegex.matches(in: fullText, options: [], range: NSRange(fullText.startIndex..., in: fullText))
            
            // 过滤掉与代码块重叠的LaTeX匹配
            latexMatches = latexMatches.filter { latexMatch in
                !excludedRanges.contains { excludedRange in
                    NSIntersectionRange(latexMatch.range, excludedRange).length > 0
                }
            }
            
            for match in latexMatches {
                let range = match.range
                let fullLatexContent = (fullText as NSString).substring(with: range)
                allMatches.append((range, .latex(fullLatexContent)))
                excludedRanges.append(range)
            }
            
            // 3. 匹配行内LaTeX
            let inlineLatexRegex = try NSRegularExpression(pattern: "\\$([^$\\n]+?)\\$", options: [])
            var inlineLatexMatches = inlineLatexRegex.matches(in: fullText, options: [], range: NSRange(fullText.startIndex..., in: fullText))
            
            // 过滤掉与已处理区域重叠的匹配
            inlineLatexMatches = inlineLatexMatches.filter { latexMatch in
                !excludedRanges.contains { excludedRange in
                    NSIntersectionRange(latexMatch.range, excludedRange).length > 0
                }
            }
            
            for match in inlineLatexMatches {
                let range = match.range
                let fullLatexContent = (fullText as NSString).substring(with: range)
                allMatches.append((range, .latex(fullLatexContent)))
                excludedRanges.append(range)
            }
            
            // 4. 匹配行内代码
            let inlineCodeRegex = try NSRegularExpression(pattern: "`([^`]*?)`", options: [])
            var inlineCodeMatches = inlineCodeRegex.matches(in: fullText, options: [], range: NSRange(fullText.startIndex..., in: fullText))
            
            // 过滤掉与已处理区域重叠的匹配
            inlineCodeMatches = inlineCodeMatches.filter { codeMatch in
                !excludedRanges.contains { excludedRange in
                    NSIntersectionRange(codeMatch.range, excludedRange).length > 0
                }
            }
            
            for match in inlineCodeMatches {
                let range = match.range
                let codeContent = (fullText as NSString).substring(with: match.range(at: 1))
                allMatches.append((range, .highlight(codeContent)))
                excludedRanges.append(range)
            }
            
            // 按位置排序
            allMatches.sort { $0.0.location < $1.0.location }
            
            // 提取普通文本和特殊元素
            var lastIndex = 0
            let nsText = fullText as NSString
            
            for (range, element) in allMatches {
                // 处理匹配前的普通文本
                if lastIndex < range.location {
                    let normalText = nsText.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex))
                    if !normalText.isEmpty {
                        // 将普通文本按换行符分割，并分别添加到elements中
                        let textParts = normalText.components(separatedBy: "\n")
                        for part in textParts {
                            if !part.isEmpty {
                                elements.append(.markdown(part))
                            }
                        }
                    }
                }
                
                // 添加特殊元素
                elements.append(element)
                
                lastIndex = range.location + range.length
            }
            
            // 处理最后一段普通文本
            if lastIndex < nsText.length {
                let finalText = nsText.substring(from: lastIndex)
                if !finalText.isEmpty {
                    // 同样处理最后一段文本的换行
                    let textParts = finalText.components(separatedBy: "\n")
                    for part in textParts {
                        if !part.isEmpty {
                            elements.append(.markdown(part))
                        }
                    }
                }
            }
            
        } catch {
            print("Regex error: \(error)")
            // 解析失败时，将整个文本作为普通markdown处理，保留换行
            let textParts = fullText.components(separatedBy: "\n")
            for part in textParts {
                if !part.isEmpty {
                    elements.append(.markdown(part))
                }
            }
        }
        
        return elements
    }
} 
