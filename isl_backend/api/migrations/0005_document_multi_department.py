# Generated for the multi-department documents feature.
#
# Converts Document.department (a single ForeignKey) into
# Document.departments (a ManyToManyField), so one document can be
# visible to more than one department. Done in three steps so no data
# is lost:
#   1. Add the new M2M field under a temporary related_name (to avoid
#      a reverse-accessor name clash with the old FK, which still
#      exists at this point in the migration history).
#   2. Copy every document's existing single `department` into the new
#      `departments` M2M table.
#   3. Remove the old `department` FK, then rename the M2M field's
#      related_name to its final value ('documents'), now that nothing
#      else is using that name.

import django.db.models.deletion
from django.db import migrations, models


def copy_department_to_departments(apps, schema_editor):
    Document = apps.get_model('api', 'Document')
    for doc in Document.objects.all():
        if doc.department_id:
            doc.departments.add(doc.department_id)


def reverse_copy(apps, schema_editor):
    # Best-effort reverse: put each document's first linked department
    # back into the old single FK field.
    Document = apps.get_model('api', 'Document')
    for doc in Document.objects.all():
        first_dept = doc.departments.first()
        if first_dept:
            doc.department_id = first_dept.id
            doc.save(update_fields=['department_id'])


class Migration(migrations.Migration):

    dependencies = [
        ('api', '0004_alter_document_file_type'),
    ]

    operations = [
        migrations.AddField(
            model_name='document',
            name='departments',
            field=models.ManyToManyField(
                related_name='documents_new',
                to='api.department',
                db_table='documents_departments',
            ),
        ),
        migrations.RunPython(copy_department_to_departments, reverse_copy),
        migrations.RemoveIndex(
            model_name='document',
            name='documents_departm_cc5c13_idx',
        ),
        migrations.RemoveField(
            model_name='document',
            name='department',
        ),
        migrations.AlterField(
            model_name='document',
            name='departments',
            field=models.ManyToManyField(
                related_name='documents',
                to='api.department',
                db_table='documents_departments',
            ),
        ),
    ]