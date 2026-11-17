/// Reads the marks a writer puts inside a line (CONVENTIONS.md, "Marks inside
/// a line").
///
/// Springwater itself never looks inside a content line. A schema may declare
/// marks, and a presentation may say how to draw them; this type finds them.
/// The one mark defined so far is emphasis: text between two underscores.
public enum InlineMarks {

    /// A stretch of a line that is drawn one way.
    public struct Run: Sendable, Equatable {
        public let text: String
        public let isEmphasized: Bool

        public init(text: String, isEmphasized: Bool) {
            self.text = text
            self.isEmphasized = isEmphasized
        }
    }

    /// Splits one line into runs. The underscores that mark emphasis are not
    /// part of any run; every other character is kept, in order.
    ///
    /// An underscore opens emphasis when it is at the start of the line or
    /// follows a character that is not a letter, a digit, or an underscore,
    /// and the character after it is not a space, a tab, or an underscore.
    /// An underscore closes emphasis when the character before it is not a
    /// space or a tab and it is at the end of the line or is followed by a
    /// character that is not a letter, a digit, or an underscore. An opening
    /// underscore pairs with the nearest closing underscore after it that
    /// leaves at least one character between them. An underscore that pairs
    /// with nothing is ordinary text, so `snake_case` is left alone.
    public static func runs(in line: String) -> [Run] {
        let characters = Array(line)
        var runs: [Run] = []
        var plain = ""
        var index = 0

        func isWord(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }
        func isSpace(_ character: Character) -> Bool {
            character == " " || character == "\t"
        }
        func opens(at position: Int) -> Bool {
            guard characters[position] == "_", position + 1 < characters.count else { return false }
            if position > 0, isWord(characters[position - 1]) { return false }
            let next = characters[position + 1]
            return !isSpace(next) && next != "_"
        }
        func closes(at position: Int) -> Bool {
            guard characters[position] == "_", !isSpace(characters[position - 1]) else { return false }
            return position + 1 == characters.count || !isWord(characters[position + 1])
        }

        while index < characters.count {
            if opens(at: index),
               index + 2 < characters.count,
               let close = (index + 2..<characters.count).first(where: { closes(at: $0) }) {
                if !plain.isEmpty {
                    runs.append(Run(text: plain, isEmphasized: false))
                    plain = ""
                }
                runs.append(Run(text: String(characters[(index + 1)..<close]), isEmphasized: true))
                index = close + 1
            } else {
                plain.append(characters[index])
                index += 1
            }
        }
        if !plain.isEmpty {
            runs.append(Run(text: plain, isEmphasized: false))
        }
        return runs
    }
}
