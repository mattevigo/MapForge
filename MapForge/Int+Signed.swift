extension Int {
    /// A bonus as a DM writes one and the rulebook prints it: "+2", "−1", "+0" — always
    /// signed, with a true minus rather than a hyphen, as their own notes use.
    var signed: String {
        self < 0 ? "−\(-self)" : "+\(self)"
    }
}
