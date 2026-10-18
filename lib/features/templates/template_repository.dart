import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../periods/models.dart';

class TemplateItem {
  TemplateItem({required this.name, this.categoryId, this.planned = 0});
  String name;
  String? categoryId;
  double planned;
}

class ExpenseTemplate {
  const ExpenseTemplate({required this.id, required this.name, required this.items});
  final String id, name;
  final List<TemplateItem> items;
  double get total => items.fold(0, (s, i) => s + i.planned);

  factory ExpenseTemplate.fromMap(Map<String, dynamic> m) => ExpenseTemplate(
        id: m['id'] as String,
        name: m['name'] as String,
        items: ((m['template_items'] as List?) ?? [])
            .map((i) => TemplateItem(
                  name: i['name'] as String,
                  categoryId: i['category_id'] as String?,
                  planned: num0(i['planned_amount']),
                ))
            .toList(),
      );
}

class TemplateRepository {
  TemplateRepository(this._c);
  final SupabaseClient _c;

  Future<List<ExpenseTemplate>> list() async {
    final r = await _c.from('templates').select('*, template_items(*)').order('name');
    return r.map<ExpenseTemplate>(ExpenseTemplate.fromMap).toList();
  }

  Future<void> save({String? id, required String name, required List<TemplateItem> items}) async {
    final String tid;
    if (id == null) {
      final r = await _c.from('templates').insert({'name': name}).select('id').single();
      tid = r['id'] as String;
    } else {
      await _c.from('templates').update({'name': name}).eq('id', id);
      await _c.from('template_items').delete().eq('template_id', id);
      tid = id;
    }
    if (items.isNotEmpty) {
      await _c.from('template_items').insert([
        for (final i in items)
          {'template_id': tid, 'name': i.name, 'category_id': i.categoryId, 'planned_amount': i.planned},
      ]);
    }
  }

  Future<void> delete(String id) => _c.from('templates').delete().eq('id', id);
}

final templateRepositoryProvider = Provider((ref) => TemplateRepository(ref.watch(supabaseProvider)));

final templatesProvider = FutureProvider<List<ExpenseTemplate>>((ref) {
  ref.watch(userIdProvider);
  return ref.watch(templateRepositoryProvider).list();
});
