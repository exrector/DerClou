import Foundation
import RealityKit

let modelPath = "/Users/exrector/Documents/PROJECTS/DerClou/ArtSource/Characters/Guard03/guard03.usdz"
let url = URL(fileURLWithPath: modelPath)

do {
    let entity = try Entity.load(contentsOf: url)
    var found = false
    func traverse(_ ent: Entity) {
        if let model = ent as? ModelEntity, let _ = model.model?.mesh {
            let jointNames = model.jointNames
            if !jointNames.isEmpty {
                print("Joints: \(jointNames.prefix(10))... (total: \(jointNames.count))")
                for j in jointNames {
                    if j.lowercased().contains("arm") || j.lowercased().contains("shoulder") || j.lowercased().contains("spine") {
                        print(" - \(j)")
                    }
                }
                found = true
            }
        }
        for child in ent.children {
            traverse(child)
        }
    }
    traverse(entity)
    if !found {
        print("No ModelEntity with jointNames found.")
    }
} catch {
    print("Error: \(error)")
}
