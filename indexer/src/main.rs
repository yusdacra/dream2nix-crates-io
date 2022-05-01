#![deny(rust_2018_idioms)]

use indexer::*;

fn main() {
    let settings: Settings = std::env::args()
        .nth(1)
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_else(|| serde_json::from_str("{}").expect("is valid"));

    let mut indexer = Indexer::new(settings).page_callback(Box::new(|page, url| {
        eprintln!("fetching page {page} from '{url}'")
    }));

    let infos = indexer.generate_info();

    let serialized =
        serde_json::to_string(&infos).expect("could not serialize crate information to JSON");
    println!("{}", serialized);
}
