use notify::{
    recommended_watcher, Config, Event, EventKind, PollWatcher, RecursiveMode, Watcher, WatcherKind,
};
use notify_debouncer_mini::{new_debouncer, DebounceEventResult, DebouncedEventKind, Debouncer};
use rustler::{Atom, Error, NifResult};
use std::collections::HashMap;
use std::path::Path;
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        created,
        modified,
        removed,
        renamed,
        meta,
        file,
        directory,
        unknown,
        recommended,
        poll,
        inotify,
        fsevent,
        kqueue,
        windows,
        null,
        invalid_backend,
        watcher_not_found
    }
}

#[derive(Debug, Clone)]
enum BackendType {
    Recommended,
    Poll,
    #[cfg(target_os = "linux")]
    INotify,
    #[cfg(target_os = "macos")]
    FsEvent,
    #[cfg(target_os = "windows")]
    Windows,
    Null,
}

type WatcherResult = Result<
    (
        Box<dyn Watcher + Send>,
        mpsc::Receiver<Result<Event, notify::Error>>,
        WatcherKind,
    ),
    Error,
>;

enum WatcherType {
    Regular {
        #[allow(dead_code)] // Keep watcher alive for file monitoring
        watcher: Box<dyn Watcher + Send>,
        receiver: mpsc::Receiver<Result<Event, notify::Error>>,
    },
    Debounced {
        #[allow(dead_code)] // Keep debouncer alive for file monitoring
        debouncer: Debouncer<notify::RecommendedWatcher>,
        receiver: mpsc::Receiver<DebounceEventResult>,
    },
}

struct WatcherInfo {
    watcher_type: WatcherType,
    backend_kind: WatcherKind,
    path: String,
    recursive: bool,
    #[allow(dead_code)] // Used for info/debugging purposes
    debounce_ms: Option<u64>,
}

// Global storage for watchers
static NEXT_WATCHER_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
static WATCHERS: once_cell::sync::Lazy<Arc<Mutex<HashMap<u64, WatcherInfo>>>> =
    once_cell::sync::Lazy::new(|| Arc::new(Mutex::new(HashMap::new())));

impl BackendType {
    fn from_atom(atom: Atom) -> Result<Self, Error> {
        if atom == atoms::recommended() {
            Ok(BackendType::Recommended)
        } else if atom == atoms::poll() {
            Ok(BackendType::Poll)
        } else if atom == atoms::inotify() {
            #[cfg(target_os = "linux")]
            {
                Ok(BackendType::INotify)
            }
            #[cfg(not(target_os = "linux"))]
            {
                Err(Error::BadArg)
            }
        } else if atom == atoms::fsevent() {
            #[cfg(target_os = "macos")]
            {
                Ok(BackendType::FsEvent)
            }
            #[cfg(not(target_os = "macos"))]
            {
                Err(Error::BadArg)
            }
        } else if atom == atoms::kqueue() {
            // Kqueue support requires special feature flag in notify crate
            Err(Error::BadArg)
        } else if atom == atoms::windows() {
            #[cfg(target_os = "windows")]
            {
                Ok(BackendType::Windows)
            }
            #[cfg(not(target_os = "windows"))]
            {
                Err(Error::BadArg)
            }
        } else if atom == atoms::null() {
            Ok(BackendType::Null)
        } else {
            Err(Error::BadArg)
        }
    }

    fn create_watcher(&self) -> WatcherResult {
        let (tx, rx) = mpsc::channel();

        match self {
            BackendType::Recommended => {
                let watcher = recommended_watcher(tx).map_err(|_| Error::BadArg)?;
                // Determine the backend kind based on the platform
                #[cfg(target_os = "linux")]
                let kind = WatcherKind::Inotify;
                #[cfg(target_os = "macos")]
                let kind = WatcherKind::Fsevent;
                #[cfg(target_os = "windows")]
                let kind = WatcherKind::ReadDirectoryChangesWatcher;
                #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
                let kind = WatcherKind::PollWatcher;
                Ok((Box::new(watcher), rx, kind))
            }
            BackendType::Poll => {
                let watcher = PollWatcher::new(tx, Config::default()).map_err(|_| Error::BadArg)?;
                let kind = WatcherKind::PollWatcher;
                Ok((Box::new(watcher), rx, kind))
            }
            #[cfg(target_os = "linux")]
            BackendType::INotify => {
                let watcher = notify::INotifyWatcher::new(tx, Config::default())
                    .map_err(|_| Error::BadArg)?;
                let kind = WatcherKind::Inotify;
                Ok((Box::new(watcher), rx, kind))
            }
            #[cfg(target_os = "macos")]
            BackendType::FsEvent => {
                let watcher = notify::FsEventWatcher::new(tx, Config::default())
                    .map_err(|_| Error::BadArg)?;
                let kind = WatcherKind::Fsevent;
                Ok((Box::new(watcher), rx, kind))
            }
            #[cfg(target_os = "windows")]
            BackendType::Windows => {
                let watcher = notify::ReadDirectoryChangesWatcher::new(tx, Config::default())
                    .map_err(|_| Error::BadArg)?;
                let kind = WatcherKind::ReadDirectoryChangesWatcher;
                Ok((Box::new(watcher), rx, kind))
            }
            BackendType::Null => {
                let watcher =
                    notify::NullWatcher::new(tx, Config::default()).map_err(|_| Error::BadArg)?;
                let kind = WatcherKind::NullWatcher;
                Ok((Box::new(watcher), rx, kind))
            }
        }
    }
}

fn start_watcher_internal(
    path: String,
    recursive: bool,
    backend: BackendType,
    debounce_ms: Option<u64>,
) -> NifResult<(Atom, u64)> {
    let watch_path = Path::new(&path);
    let mode = if recursive {
        RecursiveMode::Recursive
    } else {
        RecursiveMode::NonRecursive
    };

    let id = NEXT_WATCHER_ID.fetch_add(1, std::sync::atomic::Ordering::SeqCst);

    let watcher_info = match debounce_ms {
        Some(ms) => {
            // Create debounced watcher
            let (tx, rx) = mpsc::channel();
            let mut debouncer = new_debouncer(
                Duration::from_millis(ms),
                move |result: DebounceEventResult| {
                    let _ = tx.send(result);
                },
            )
            .map_err(|_| Error::BadArg)?;

            // Watch the path
            debouncer
                .watcher()
                .watch(watch_path, mode)
                .map_err(|_| Error::BadArg)?;

            // Determine the backend kind based on the platform (debouncer uses recommended watcher)
            #[cfg(target_os = "linux")]
            let backend_kind = WatcherKind::Inotify;
            #[cfg(target_os = "macos")]
            let backend_kind = WatcherKind::Fsevent;
            #[cfg(target_os = "windows")]
            let backend_kind = WatcherKind::ReadDirectoryChangesWatcher;
            #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
            let backend_kind = WatcherKind::PollWatcher;

            WatcherInfo {
                watcher_type: WatcherType::Debounced {
                    debouncer,
                    receiver: rx,
                },
                backend_kind,
                path: path.clone(),
                recursive,
                debounce_ms: Some(ms),
            }
        }
        None => {
            // Create regular watcher
            let (mut watcher, receiver, backend_kind) = backend.create_watcher()?;
            watcher.watch(watch_path, mode).map_err(|_| Error::BadArg)?;

            WatcherInfo {
                watcher_type: WatcherType::Regular { watcher, receiver },
                backend_kind,
                path: path.clone(),
                recursive,
                debounce_ms: None,
            }
        }
    };

    let mut watchers = WATCHERS.lock().unwrap();
    watchers.insert(id, watcher_info);

    Ok((atoms::ok(), id))
}

#[rustler::nif]
fn start_watcher(path: String, recursive: bool) -> NifResult<(Atom, u64)> {
    start_watcher_internal(path, recursive, BackendType::Recommended, None)
}

#[rustler::nif]
fn start_watcher_with_backend(
    path: String,
    recursive: bool,
    backend_atom: Atom,
) -> NifResult<(Atom, u64)> {
    let backend = BackendType::from_atom(backend_atom)?;
    start_watcher_internal(path, recursive, backend, None)
}

#[rustler::nif]
fn start_watcher_with_debounce(
    path: String,
    recursive: bool,
    backend_atom: Atom,
    debounce_ms: u64,
) -> NifResult<(Atom, u64)> {
    let backend = BackendType::from_atom(backend_atom)?;
    start_watcher_internal(path, recursive, backend, Some(debounce_ms))
}

#[rustler::nif]
fn stop_watcher(id: u64) -> Atom {
    let mut watchers = WATCHERS.lock().unwrap();
    if watchers.remove(&id).is_some() {
        atoms::ok()
    } else {
        atoms::watcher_not_found()
    }
}

#[rustler::nif]
fn get_events(id: u64) -> NifResult<Vec<(Atom, String, Atom)>> {
    let mut watchers = WATCHERS.lock().unwrap();

    if let Some(watcher_info) = watchers.get_mut(&id) {
        let mut events = Vec::new();

        match &mut watcher_info.watcher_type {
            WatcherType::Regular { receiver, .. } => {
                // Handle regular watcher events
                while let Ok(result) = receiver.try_recv() {
                    match result {
                        Ok(event) => {
                            for path in event.paths {
                                let event_atom = event_kind_to_atom(&event.kind);
                                let path_str = path_to_string(&path);
                                let file_type_atom = if path.is_dir() {
                                    atoms::directory()
                                } else {
                                    atoms::file()
                                };

                                events.push((event_atom, path_str, file_type_atom));
                            }
                        }
                        Err(_) => {
                            // Error in file watching, but we'll continue
                            continue;
                        }
                    }
                }
            }
            WatcherType::Debounced { receiver, .. } => {
                // Handle debounced watcher events
                while let Ok(result) = receiver.try_recv() {
                    match result {
                        Ok(debounced_events) => {
                            for event in debounced_events {
                                let event_atom = debounced_event_kind_to_atom(&event.kind);
                                let path_str = path_to_string(&event.path);
                                let file_type_atom = if event.path.is_dir() {
                                    atoms::directory()
                                } else {
                                    atoms::file()
                                };

                                events.push((event_atom, path_str, file_type_atom));
                            }
                        }
                        Err(_) => {
                            // Error in file watching, but we'll continue
                            continue;
                        }
                    }
                }
            }
        }

        Ok(events)
    } else {
        Err(Error::BadArg)
    }
}

#[rustler::nif]
fn get_watcher_info(id: u64) -> NifResult<(Atom, String, bool, Atom)> {
    let watchers = WATCHERS.lock().unwrap();

    if let Some(watcher_info) = watchers.get(&id) {
        let backend_atom = match watcher_info.backend_kind {
            WatcherKind::Inotify => atoms::inotify(),
            WatcherKind::Fsevent => atoms::fsevent(),
            WatcherKind::Kqueue => atoms::kqueue(),
            WatcherKind::PollWatcher => atoms::poll(),
            WatcherKind::ReadDirectoryChangesWatcher => atoms::windows(),
            WatcherKind::NullWatcher => atoms::null(),
            _ => atoms::unknown(),
        };

        Ok((
            atoms::ok(),
            watcher_info.path.clone(),
            watcher_info.recursive,
            backend_atom,
        ))
    } else {
        Err(Error::BadArg)
    }
}

#[rustler::nif]
fn list_available_backends() -> Vec<Atom> {
    let mut backends = vec![atoms::recommended(), atoms::poll(), atoms::null()];

    #[cfg(target_os = "linux")]
    backends.push(atoms::inotify());

    #[cfg(target_os = "macos")]
    {
        backends.push(atoms::fsevent());
        backends.push(atoms::kqueue());
    }

    #[cfg(target_os = "windows")]
    backends.push(atoms::windows());

    backends
}

fn event_kind_to_atom(kind: &EventKind) -> Atom {
    match kind {
        EventKind::Create(_) => atoms::created(),
        EventKind::Modify(_) => atoms::modified(),
        EventKind::Remove(_) => atoms::removed(),
        EventKind::Other => atoms::meta(),
        _ => atoms::unknown(),
    }
}

fn debounced_event_kind_to_atom(kind: &DebouncedEventKind) -> Atom {
    match kind {
        DebouncedEventKind::Any => atoms::modified(),
        _ => atoms::unknown(),
    }
}

fn path_to_string(path: &std::path::Path) -> String {
    path.to_string_lossy().into_owned()
}

rustler::init!("Elixir.FSNotify.Native");
