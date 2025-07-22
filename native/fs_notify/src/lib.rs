use notify::{recommended_watcher, EventKind, RecursiveMode, Watcher};
use rustler::{Error, NifResult};
use std::path::Path;
use std::sync::mpsc;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        created,
        modified,
        removed,
        renamed,
        other,
        file,
        directory,
        unknown
    }
}

// Global storage for watchers
static NEXT_WATCHER_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

#[rustler::nif]
fn start_watcher(path: String, recursive: bool) -> NifResult<(rustler::Atom, u64)> {
    let (_tx, _rx) = mpsc::channel();

    match recommended_watcher(_tx) {
        Ok(mut watcher) => {
            let watch_path = Path::new(&path);
            let mode = if recursive {
                RecursiveMode::Recursive
            } else {
                RecursiveMode::NonRecursive
            };

            match watcher.watch(watch_path, mode) {
                Ok(_) => {
                    let id = NEXT_WATCHER_ID.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    // Note: In a real implementation, you'd want to store the watcher somewhere
                    // so it doesn't get dropped. For now, we'll just return success.
                    Ok((atoms::ok(), id))
                }
                Err(_) => Err(Error::BadArg),
            }
        }
        Err(_) => Err(Error::BadArg),
    }
}

#[rustler::nif]
fn stop_watcher(_id: u64) -> rustler::Atom {
    // In a real implementation, you'd remove the watcher from storage
    atoms::ok()
}

#[rustler::nif]
fn get_events(_id: u64) -> NifResult<Vec<(rustler::Atom, String, rustler::Atom)>> {
    // In a real implementation, you'd get events from the stored receiver
    // For now, return empty list
    Ok(vec![])
}

#[allow(dead_code)]
fn event_kind_to_atom(kind: &EventKind) -> rustler::Atom {
    match kind {
        EventKind::Create(_) => atoms::created(),
        EventKind::Modify(_) => atoms::modified(),
        EventKind::Remove(_) => atoms::removed(),
        EventKind::Other => atoms::other(),
        _ => atoms::unknown(),
    }
}

#[allow(dead_code)]
fn path_to_string(path: &std::path::Path) -> String {
    path.to_string_lossy().into_owned()
}

rustler::init!("Elixir.FSNotify.Native");
