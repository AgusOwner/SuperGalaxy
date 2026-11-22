import Foundation

/// Instala automáticamente los paquetes .3106/.3105 incluidos en el bundle de
/// la app dentro de PatchProjects/, para que aparezcan solos en la pestaña
/// Installed sin que el usuario tenga que importarlos a mano.
///
/// Para agregar paquetes preinstalados, poné los archivos .3106 o .3105 en la
/// carpeta BundledPatches/ de la raíz del proyecto (folder reference azul, ya
/// incluida en Copy Bundle Resources). No hace falta tocar el pbxproj para
/// cada archivo nuevo.
///
/// Es idempotente y se puede llamar en cada arranque: solo copia lo que falta
/// o lo que cambió de tamaño, así que los paquetes nuevos de una build nueva
/// aparecen sin reinstalar la app.
///
/// Si el usuario borra un paquete preinstalado desde "Installed", NO vuelve a
/// aparecer solo (hay una marca en UserDefaults que recuerda qué ya se
/// sembró, independiente de si el archivo sigue en PatchProjects/). Solo
/// reaparece si: (a) desinstala y reinstala la app, o (b) una build nueva
/// trae una versión distinta (otro tamaño) del mismo archivo.
enum BundledPatchSeeder {

    private static let folderName = "BundledPatches"
    private static let packageExtensions: Set<String> = ["3106", "3105"]
    private static let maximumDepth = 2

    /// Marca persistente (UserDefaults, no se borra al eliminar un parche) de
    /// qué paquetes del bundle ya se sembraron alguna vez. Es lo que evita que
    /// un paquete preinstalado reaparezca solo porque el usuario lo borró —
    /// solo vuelve a aparecer si la app se desinstala y se reinstala (lo cual
    /// borra UserDefaults junto con todo lo demás) o si la build trae una
    /// versión nueva del mismo archivo (tamaño distinto → identificador
    /// distinto → se trata como un paquete nuevo).
    private static let seededMarkerKey = "argent.bundledpatches.seeded_v1"

    /// Devuelve cuántos paquetes se instalaron en esta pasada.
    @discardableResult
    static func seedIfNeeded() -> Int {
        let sources = bundledPackages()
        guard !sources.isEmpty else {
            log("seeder: no bundled packages found in the app bundle")
            return 0
        }
        guard let root = try? PatchProjectLibrary.packageRootURL() else {
            log("seeder: patch package root unavailable")
            return 0
        }

        var seeded = Set(UserDefaults.standard.stringArray(forKey: seededMarkerKey) ?? [])
        var installed = 0
        var markerChanged = false

        for source in sources {
            let name = source.lastPathComponent
            let identifier = seedIdentifier(for: source)

            // Ya se sembró esta misma versión de este paquete antes, aunque el
            // usuario lo haya borrado después. No reinstalarlo solo porque
            // ya no esté en PatchProjects/ — eso sería deshacer su borrado.
            guard !seeded.contains(identifier) else { continue }

            let destination = root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                // Ya está instalado (p. ej. de una corrida parcial anterior,
                // antes de que existiera esta marca). No lo tocamos, solo
                // registramos que ya quedó cubierto.
                seeded.insert(identifier)
                markerChanged = true
                continue
            }

            do {
                try FileManager.default.copyItem(at: source, to: destination)
                installed += 1
                seeded.insert(identifier)
                markerChanged = true
                log("seeder: installed \(name)")
                markAsAuthorCopyIfPossible(destination)
            } catch {
                log("seeder: failed to install \(name) — \(error.localizedDescription)")
            }
        }

        if markerChanged {
            UserDefaults.standard.set(Array(seeded), forKey: seededMarkerKey)
        }
        if installed > 0 {
            log("seeder: \(installed) bundled package(s) installed")
        }
        return installed
    }

    /// Identifica una versión concreta de un paquete del bundle por nombre +
    /// tamaño, para distinguir "ya lo sembré antes" de "esta build trae una
    /// versión nueva de este mismo archivo".
    private static func seedIdentifier(for url: URL) -> String {
        "\(url.lastPathComponent)#\(fileSize(url) ?? -1)"
    }

    private static func markAsAuthorCopyIfPossible(_ url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let summary = try? PatchPackageCodec.inspect(data) else { return }
        try? PatchProjectLibrary.markAsAuthorCopy(packageID: summary.packageID)
    }

    private static func bundledPackages() -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()
        for directory in candidateDirectories() {
            for url in packages(in: directory) where seen.insert(url.lastPathComponent).inserted {
                results.append(url)
            }
        }
        return results
    }

    /// El folder reference se copia a la raíz del .app. Se cubren también
    /// variantes por si el recurso queda aplanado en la raíz del bundle.
    private static func candidateDirectories() -> [URL] {
        let bundles = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        var directories: [URL] = []
        for bundle in bundles {
            let nested = bundle.appendingPathComponent(folderName, isDirectory: true)
            if isDirectory(nested) { directories.append(nested) }
            if isDirectory(bundle) { directories.append(bundle) }
        }
        return directories
    }

    private static func packages(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let baseDepth = directory.standardizedFileURL.pathComponents.count
        var results: [URL] = []

        for case let url as URL in enumerator {
            let depth = url.standardizedFileURL.pathComponents.count - baseDepth
            guard depth <= maximumDepth else {
                enumerator.skipDescendants()
                continue
            }
            guard packageExtensions.contains(url.pathExtension.lowercased()),
                  isFile(url) else { continue }
            results.append(url)
        }
        return results
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    private static func isFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
