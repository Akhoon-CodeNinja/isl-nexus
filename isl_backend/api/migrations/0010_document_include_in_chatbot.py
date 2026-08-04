# Generated for: Document.include_in_chatbot (chatbot indexing opt-in)

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('api', '0009_user_chat_daily_limit_override_notificationtemplate'),
    ]

    operations = [
        migrations.AddField(
            model_name='document',
            name='include_in_chatbot',
            field=models.BooleanField(
                default=False,
                db_index=True,
                help_text=(
                    "If True, this document's content is embedded into the AI "
                    "chatbot's searchable knowledge base. If False, it's still "
                    "readable/downloadable normally but never surfaced in AI "
                    "chat answers. Settable by a Department Head or Admin only."
                ),
            ),
        ),
    ]
