"""Synthetic legacy/current SQLite snapshots; no user collection data.
Run from any directory to regenerate. Intentionally does not use today's encoder:
these frozen table/JSON shapes exercise compatibility with distributed formats.
"""
import json
import sqlite3
from pathlib import Path

for version in (1, 2):
    path = Path(__file__).with_name(f'migration-schema{version}.sqlite')
    path.unlink(missing_ok=True)
    with sqlite3.connect(path) as db:
        db.executescript(f'''PRAGMA application_id=1229476932;
PRAGMA user_version={version};
CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE items(id INTEGER PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE tags(id INTEGER PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE views(id INTEGER PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE links(parent INTEGER NOT NULL, child INTEGER NOT NULL, position INTEGER NOT NULL, PRIMARY KEY(parent,child));''')
        metadata = {'document_id': 'synthetic-upgrade-collection', 'schema_version': str(version), 'revision': '42', 'next_id': '9'}
        if version == 2:
            metadata.update(root_order='[2,3]', deleted_item_ids='[]')
        db.executemany('INSERT INTO metadata VALUES (?,?)', metadata.items())
        for id, kind, title in [(2,'folder','Trip'), (3,'folder','Home'), (4,'task','Pack passport'), (5,'task','Completed task')]:
            item = dict(id=id, kind=kind, title=title, notes='Synthetic notes 日本', due_date='2026-12-01' if id==4 else None, priority=3 if id==4 else 0, completed=id==5, auto_complete=False, tag_ids=[6] if id==4 else [])
            db.execute('INSERT INTO items VALUES (?,?)',(id,json.dumps(item)))
        db.execute('INSERT INTO tags VALUES (?,?)',(6,json.dumps(dict(id=6,name='Travel'))))
        for view in [dict(id=1,name='All tasks',filter=dict(op='all'),preferences={}), dict(id=7,name='Custom travel',filter=dict(op='and',rules=[dict(op='tag',tag_id=6),dict(op='folder',folder_id=2,recursive=True)]),preferences={'2': dict(hide_completed=False,inherit_hide_completed=True,folder_hidden=False,reappear_on_new=True)})]:
            db.execute('INSERT INTO views VALUES (?,?)',(view['id'],json.dumps(view)))
        db.executemany('INSERT INTO links VALUES (?,?,?)',[(2,4,0),(2,5,1),(3,4,2)])

# Later semantic-upgrade fixtures: an old default was customized, and the
# private working copy contains a separate, unpublished accepted edit.
for pending in (False, True):
    source = Path(__file__).with_name('migration-schema2.sqlite')
    path = source.with_name('protected-view-pending.sqlite' if pending else 'protected-view-customized.sqlite')
    path.unlink(missing_ok=True)
    path.write_bytes(source.read_bytes())
    with sqlite3.connect(path) as db:
        view = json.loads(db.execute('SELECT data FROM views WHERE id=1').fetchone()[0])
        view.update(name='My travel', filter=dict(op='tag', tag_id=6),
                    sorting={'0': dict(mode='title', descending=True)},
                    preferences={'2': dict(hide_completed=False, inherit_hide_completed=True,
                                           folder_hidden=False, reappear_on_new=True)})
        db.execute('UPDATE views SET data=? WHERE id=1', (json.dumps(view),))
        settings = dict(tag_suggestion_count=3, tag_half_life_days=7,
                        indicators=dict(total=True, completed_ratio=True, high_priority=True,
                                        medium_priority=False, low_priority=False, next_due_date=True))
        for key, value in dict(collection_settings=settings,
                               parent_indicator_defaults={'2': dict(total=False)},
                               tag_usage={'6': {'1793404800': 2}}).items():
            db.execute('INSERT INTO metadata VALUES (?,?)', (key, json.dumps(value)))
        if pending:
            item = json.loads(db.execute('SELECT data FROM items WHERE id=4').fetchone()[0])
            item['title'] = 'Unpublished accepted title'
            db.execute('UPDATE items SET data=? WHERE id=4', (json.dumps(item),))
            db.execute("UPDATE metadata SET value='43' WHERE key='revision'")
