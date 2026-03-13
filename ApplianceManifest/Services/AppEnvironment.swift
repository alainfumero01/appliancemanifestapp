import Foundation

struct AppEnvironment {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let functionsURL: URL

    init(bundle: Bundle = .main) throws {
        guard
            let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            !urlString.isEmpty
        else {
            throw AppError.missingConfiguration("SUPABASE_URL")
        }

        guard
            let anonKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty
        else {
            throw AppError.missingConfiguration("SUPABASE_ANON_KEY")
        }

        let functionURLString = (bundle.object(forInfoDictionaryKey: "SUPABASE_FUNCTIONS_URL") as? String)
            ?? url.appending(path: "/functions/v1").absoluteString

        guard let functionsURL = URL(string: functionURLString) else {
            throw AppError.missingConfiguration("SUPABASE_FUNCTIONS_URL")
        }

        self.supabaseURL = url
        self.supabaseAnonKey = anonKey
        self.functionsURL = functionsURL
    }
}
