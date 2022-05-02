#![deny(rust_2018_idioms)]

use indexer::*;
use microserde::json;

fn main() {
    let settings: Settings = std::env::args()
        .nth(1)
        .and_then(|raw| json::from_str(&raw).ok())
        .unwrap_or_else(Default::default);

    let mut indexer = Indexer::new(settings).page_callback(Box::new(|page, url| {
        eprintln!("fetching page {page} from '{url}'")
    }));

    let infos = indexer.generate_info();

    let serialized = json::to_string(&infos);
    println!("{}", serialized);
}
