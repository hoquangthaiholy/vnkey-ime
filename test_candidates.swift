import Cocoa
import InputMethodKit

func test(candidates: IMKCandidates) {
    candidates.updateCandidates()
    candidates.show()
}
