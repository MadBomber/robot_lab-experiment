ActiveRecordDoctor.configure do
  # Solid Queue and Solid Cable each own a separate database (see
  # config/database.yml's queue/cable roles). active_record_doctor inspects
  # every table/model it finds via ActiveRecord::Base's connection regardless
  # of which database role actually owns it, so without this it crashes
  # trying to read solid_cable_messages/solid_queue_* columns through the
  # wrong connection.
  global :ignore_tables, [
    "ar_internal_metadata",
    "schema_migrations",
    /^solid_queue_/,
    /^solid_cable_/
  ]
  global :ignore_models, [
    /^SolidQueue::/,
    "SolidCable::Message",
    "SolidCache::Entry",

    # Rails framework features this app doesn't use -- no migrations for
    # their tables exist, so active_record_doctor otherwise reports every
    # one of them as "references a non-existent table".
    "ActionMailbox::InboundEmail",
    "ActionText::EncryptedRichText",
    "ActionText::RichText",
    "ActiveStorage::Attachment",
    "ActiveStorage::Blob",
    "ActiveStorage::VariantRecord"
  ]
end
