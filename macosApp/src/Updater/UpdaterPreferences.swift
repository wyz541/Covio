import Foundation

struct UpdaterPreferenceStore {
    let paths: UpdaterPaths

    func isAutomaticUpdateEnabled(for uid: uid_t) -> Bool {
        guard let data = try? Data(contentsOf: paths.preference(for: uid)),
              let preference = try? JSONDecoder().decode(
                  UpdaterAutomaticPreference.self,
                  from: data
              ),
              preference.schemaVersion == 1
        else {
            return true
        }
        return preference.automaticUpdatesEnabled
    }
}
