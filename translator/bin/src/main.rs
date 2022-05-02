use indexer::*;
use itertools::Itertools;
use std::{env, fs, path::PathBuf, process::Command, sync::mpsc, time::Instant};

type Result<T> = core::result::Result<T, Box<dyn std::error::Error>>;

fn main() {
    let start = Instant::now();

    let raw_index = fs::read_to_string("./index.json").expect("could not read index");
    let index: Vec<CrateInformation> =
        microserde::json::from_str(&raw_index).expect("could not parse index as JSON");
    let index_len = index.len();

    let task_num = env::var("TASK_COUNT")
        .ok()
        .and_then(|raw| raw.parse::<usize>().ok())
        .unwrap_or(4);
    let (tx_success, rx_success) = mpsc::channel();

    let mut tasks = Vec::with_capacity(task_num);
    for chunk in index.into_iter().chunks(index_len / task_num).into_iter() {
        let infos = chunk.collect_vec();
        let tx_success = tx_success.clone();
        let handle = std::thread::spawn(move || {
            for info in infos {
                match translate_and_write(&info) {
                    Ok(wrote_to) => {
                        println!("wrote lock file to '{}'", wrote_to.display());
                        let _ = tx_success.send(info);
                    }
                    Err(err) => {
                        let err_msg = err.to_string();
                        if err_msg.contains("'Cargo.lock' missing") {
                            eprintln!(
                                "'{}-{}' has no Cargo.lock, skipping",
                                info.name, info.version
                            );
                        } else {
                            eprintln!(
                                "error while translating '{}-{}':\n{}",
                                info.name, info.version, err_msg
                            );
                        }
                    }
                }
            }
        });
        tasks.push(handle);
    }

    for handle in tasks {
        handle.join().expect("task panicked");
    }

    let mut succeeded_crates = Vec::new();
    while let Ok(info) = rx_success.try_recv() {
        succeeded_crates.push(info);
    }

    println!(
        "{} out of {} successfully translated!",
        succeeded_crates.len(),
        index_len
    );

    let index = microserde::json::to_string(&succeeded_crates);
    fs::write("./locks/index.json", index).expect("could not write index");
    println!("wrote succeeded crates to './locks/index.json'");

    println!("done in {:.1} seconds", start.elapsed().as_secs_f32());
}

fn translate_and_write(info: &CrateInformation) -> Result<PathBuf> {
    // generate dream lock
    let expr = format!("(builtins.getFlake (toString ./.)).lib.${{builtins.currentSystem}}.dreamLockFor \"{}\" \"{}\"", info.name, info.version);
    let raw_dream_lock = nix(["eval", "--impure", "--expr", &expr])?;
    let dream_lock = raw_dream_lock
        .trim()
        .trim_start_matches('"')
        .trim_end_matches('"')
        .replace("\\", "");

    // create lock path, create lock dir
    let lock_path: PathBuf =
        format!("./locks/{}/{}/dream-lock.json", info.name, info.version).into();
    fs::create_dir_all(lock_path.parent().unwrap())?;

    // write lock
    fs::write(&lock_path, dream_lock)?;

    Ok(lock_path)
}

fn nix<'a>(args: impl AsRef<[&'a str]>) -> Result<String> {
    run("nix", args)
}

fn run<'a>(cmd: &str, args: impl AsRef<[&'a str]>) -> Result<String> {
    if env::var_os("VERBOSE").is_some() {
        eprintln!(
            "+{}{}",
            cmd,
            args.as_ref().iter().fold(String::new(), |mut tot, item| {
                tot.push(' ');
                tot.push_str(item);
                tot
            })
        );
    }

    let output = Command::new(cmd).args(args.as_ref()).output()?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        let err = format!(
            "stderr:\n{}\nstdout:\n{}\n",
            String::from_utf8_lossy(&output.stderr),
            String::from_utf8_lossy(&output.stdout)
        );
        Err(err.into())
    }
}
