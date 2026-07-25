//! Recall has to survive how people actually ask.
//!
//! Bare-keyword tests pass trivially under AND semantics and hide the real
//! failure: a question like "护照在哪" tokenizes to 护/照/在/哪, and no stored
//! memory contains 哪, so every result disappears. These cases are phrased the
//! way the UI's own placeholder phrases them.

use std::sync::Arc;

use mewmew_core::{MemoryKind, MewmewCore, NewMemory};

fn note(core: &MewmewCore, raw_text: &str, title: &str, now: i64) {
    core.add_memory(
        NewMemory {
            kind: MemoryKind::Note,
            raw_text: raw_text.to_owned(),
            title: title.to_owned(),
            due_at: None,
            question: None,
            answer: None,
        },
        now,
    )
    .expect("add_memory");
}

fn seeded_core(name: &str) -> Arc<MewmewCore> {
    let dir = std::env::temp_dir().join(format!("mewmew-recall-{name}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("create temp dir");
    let path = dir.join("recall.sqlite3");
    let _ = std::fs::remove_file(&path);
    let core = MewmewCore::new(path.to_string_lossy().into_owned()).expect("open core");

    note(&core, "护照放在书房第二个抽屉里", "护照位置", 1_000);
    note(&core, "车停在 P3 层 B 区 42 号", "停车位置", 1_001);
    note(&core, "王医生的电话是 807-555-0199", "王医生电话", 1_002);
    note(&core, "房东说下个月租金涨到 1450", "租金上涨", 1_003);
    note(&core, "咖啡机滤芯型号 CM-200,宜家有卖", "滤芯型号", 1_004);
    core
}

#[test]
fn recall_finds_the_right_memory_across_natural_phrasings() {
    let core = seeded_core("phrasing");
    let cases = [
        ("护照", "护照位置"),
        ("护照在哪", "护照位置"),
        ("我把护照放哪了", "护照位置"),
        ("护照在哪儿呢", "护照位置"),
        ("抽屉", "护照位置"),
        ("停车", "停车位置"),
        ("车停在哪", "停车位置"),
        ("医生电话", "王医生电话"),
        ("王医生的电话是多少", "王医生电话"),
        ("房东说了什么", "租金上涨"),
        ("咖啡机滤芯什么型号", "滤芯型号"),
        ("CM-200", "滤芯型号"),
        ("807", "王医生电话"),
    ];

    for (query, expected_title) in cases {
        let hits = core
            .search_for_recall(query.to_owned(), 5)
            .expect("search_for_recall");
        assert!(
            hits.iter().any(|memory| memory.title == expected_title),
            "query {query:?} should surface {expected_title:?}, got {:?}",
            hits.iter().map(|m| &m.title).collect::<Vec<_>>()
        );
    }
}

#[test]
fn recall_ranks_the_intended_memory_first_for_a_question() {
    let core = seeded_core("ranking");
    let hits = core
        .search_for_recall("我把护照放哪了".to_owned(), 5)
        .expect("search_for_recall");
    assert_eq!(
        hits.first().map(|memory| memory.title.as_str()),
        Some("护照位置")
    );
}

/// The loose fallback trades precision for recall: a single shared character
/// (飞机 vs 咖啡机) is enough to surface a row. That is deliberate — retrieval
/// over-fetches and the answering model is instructed to say it does not know
/// rather than answer from a weak match — but it must not go unnoticed, so the
/// behaviour is pinned here.
#[test]
fn recall_widens_rather_than_returning_nothing() {
    let core = seeded_core("widening");
    let hits = core
        .search_for_recall("飞机".to_owned(), 5)
        .expect("search_for_recall");
    assert!(
        !hits.is_empty(),
        "the loose pass is expected to surface a weak character match"
    );

    let none = core
        .search_for_recall("zzz".to_owned(), 5)
        .expect("search_for_recall");
    assert!(
        none.is_empty(),
        "a query sharing nothing should find nothing"
    );
}
