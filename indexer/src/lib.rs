#![deny(rust_2018_idioms)]

use cargo::{
    core::{Dependency, Source, SourceId},
    sources::RegistrySource,
    util::{Config, VersionExt},
};
use curl::easy::Easy as Curl;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashSet};

/// A mapping of a crates name to its identifier used in source code
#[derive(Debug, Serialize)]
pub struct CrateInformation {
    pub name: String,
    pub version: String,
}

/// Hand-curated changes to the crate list
#[derive(Debug, Default, Deserialize)]
pub struct Modifications {
    #[serde(default)]
    pub exclusions: Vec<String>,
    #[serde(default)]
    pub additions: BTreeSet<String>,
}

impl Modifications {
    fn excluded(&self, name: &str) -> bool {
        self.exclusions.iter().any(|n| n == name)
    }
}

const fn max_pages_num() -> u32 {
    1
}

fn sort_by_default() -> String {
    "downloads".to_string()
}

#[derive(Debug, Default, Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub modifications: Modifications,
    /// Enable verbose logging.
    #[serde(default)]
    pub verbose: bool,
    /// Amount of pages to fetch from crates.io. Minimum is `1`.
    #[serde(default = "max_pages_num")]
    pub max_pages: u32,
    /// What to sort by. This is passed to the crates.io API as is.
    /// can be "downloads", "recent-downloads", "recent-updates" or "new".
    #[serde(default = "sort_by_default")]
    pub sort_by: String,
}

type PageCallback = Box<dyn FnMut(u32, &str)>;

pub struct Indexer {
    settings: Settings,
    http: Curl,
    page_callback: PageCallback,
}

impl Indexer {
    pub fn new(settings: Settings) -> Self {
        Self {
            settings,
            http: Curl::new(),
            page_callback: Box::new(|_, _| ()),
        }
    }

    pub fn page_callback(mut self, f: PageCallback) -> Self {
        self.page_callback = f;
        self
    }

    pub fn generate_info(&mut self) -> Vec<CrateInformation> {
        // Setup to interact with cargo.
        let config = Config::default().expect("Unable to create default Cargo config");
        let _lock = config.acquire_package_cache_lock();
        let crates_io = SourceId::crates_io(&config).expect("Unable to create crates.io source ID");
        let mut source = RegistrySource::remote(crates_io, &HashSet::new(), &config);
        source.update().expect("Unable to update registry");

        let mut top = self.fetch_top_crates();
        top.add_curated_crates(&self.settings.modifications);

        // Find the newest (non-prerelease, non-yanked) versions of all
        // the interesting crates.
        let mut summaries = Vec::new();
        for Crate { name } in &top.crates {
            if self.settings.modifications.excluded(name) {
                continue;
            }

            // Query the registry for a summary of this crate.
            // Usefully, this doesn't seem to include yanked versions
            let dep = Dependency::parse(name, None, crates_io)
                .unwrap_or_else(|e| panic!("Unable to parse dependency for {}: {}", name, e));

            let matches = source.query_vec(&dep).unwrap_or_else(|e| {
                panic!("Unable to query registry for {}: {}", name, e);
            });

            // Find the newest non-prelease version
            let maybe_summary = matches
                .into_iter()
                .filter(|summary| !summary.version().is_prerelease())
                .max_by_key(|summary| summary.version().clone());
            let summary = if let Some(summary) = maybe_summary {
                summary
            } else {
                eprintln!("Registry has no viable versions of {}, skipping", name);
                continue;
            };

            // Add a dependency on this crate.
            summaries.push(summary);
        }

        // Remove invalid and excluded packages that have been added due to resolution
        let mut packages: Vec<_> = summaries
            .into_iter()
            .filter(|summary| {
                !self
                    .settings
                    .modifications
                    .excluded(summary.name().as_str())
            })
            .collect();

        // Sort all packages by name then version (descending), so that
        // when we group them we know we get all the same crates together
        // and the newest version first.
        packages.sort_by(|a, b| {
            a.name()
                .cmp(&b.name())
                .then(a.version().cmp(&b.version()).reverse())
        });

        packages
            .into_iter()
            .map(|pkg| CrateInformation {
                name: pkg.name().to_string(),
                version: pkg.version().to_string(),
            })
            .collect()
    }

    fn fetch_top_crates(&mut self) -> TopCrates {
        let mut top = self.fetch_top_crates_page(1);
        for page in 2..=self.settings.max_pages {
            let mut page_top = self.fetch_top_crates_page(page);
            top.append(&mut page_top);
        }
        top
    }

    fn fetch_top_crates_page(&mut self, page: u32) -> TopCrates {
        let url = format!(
            "https://crates.io/api/v1/crates?page={page}&per_page=100&sort={}",
            self.settings.sort_by
        );
        (self.page_callback)(page, &url);
        let (body, status) = self.http_get(&url);
        assert!(
            status == 200,
            "Could not download top crates; HTTP status was {}",
            status
        );
        let resp = String::from_utf8(body).expect("could not parse top crates as UTF-8 text");

        serde_json::from_str(&resp).expect("could not parse top crates as JSON")
    }

    fn http_get(&mut self, url: &str) -> (Vec<u8>, u32) {
        let mut body = Vec::new();

        self.http.url(url).expect("could not set url");
        self.http
            .verbose(self.settings.verbose)
            .expect("could not set verbose");
        self.http
            .useragent("dream2nix crates-io top crates fetcher")
            .expect("could not set user agent");

        let mut transfer = self.http.transfer();
        transfer
            .write_function(|data| {
                body.extend_from_slice(data);
                Ok(data.len())
            })
            .expect("could not set write callback");
        transfer.perform().expect("failed to make request");
        drop(transfer);

        let status = self
            .http
            .response_code()
            .expect("failed to get response status");

        (body, status)
    }
}

/// The shared description of a crate
#[derive(Debug, Deserialize)]
struct Crate {
    #[serde(rename = "id")]
    name: String,
}

/// The list of crates from crates.io
#[derive(Debug, Deserialize)]
struct TopCrates {
    crates: Vec<Crate>,
}

impl TopCrates {
    fn append(&mut self, other: &mut TopCrates) {
        self.crates.append(&mut other.crates);
    }

    /// Add crates that have been hand-picked
    fn add_curated_crates(&mut self, modifications: &Modifications) {
        self.crates.extend({
            modifications
                .additions
                .iter()
                .cloned()
                .map(|name| Crate { name })
        });
    }
}
