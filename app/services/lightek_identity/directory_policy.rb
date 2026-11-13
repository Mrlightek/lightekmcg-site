module LightekIdentity
  module DirectoryPolicy
    # Called inside the membership/grant mutation transaction, not after commit.
    def self.changed!(employer_id)
      return unless Realm.table_exists?
      Realm.where(employer_id: employer_id).update_all('directory_revision = directory_revision + 1')
    end
    def self.calendar!(realm)
      realm.with_lock do
        if realm.calendar_on != Date.current
          realm.update_columns(calendar_on: Date.current,directory_revision: realm.directory_revision + 1)
        end
      end
      realm.reload
    end
  end
end
