# frozen_string_literal: true
require 'fileutils'
module NevaehOs
  # Only the orchestrator calls this writer. Workers return values, never append files.
  module ReportJournal
    MAX_READ=8*1024*1024
    module_function
    def reference(actor_id:,task_id:,receipt_sha256:)
      "journal:#{Integer(actor_id)}:#{task_id}:#{receipt_sha256}"
    end
    def resolve!(actor:,report_ref:)
      match=/\Ajournal:([1-9][0-9]*):([0-9a-f-]{36}):([0-9a-f]{64})\z/.match(report_ref.to_s)
      raise ArgumentError,'Unresolvable report_ref' unless match && match[1].to_i==actor.id
      value=read!(actor,task_id:match[2])[match[2]]
      unless value && value['schema_version']==2 && value.dig('output','receipt_sha256')==match[3]
        raise ArgumentError,'Referenced journal report is missing or stale'
      end
      value
    end
    def root = Rails.root.join('storage','nevaeh_worker_reports')
    def directories!(target)
      target.ascend.to_a.reverse_each do |directory|
        raise ArgumentError,'Managed storage cannot contain symbolic links' if File.symlink?(directory)
        begin
          Dir.mkdir(directory,0700) unless File.directory?(directory)
        rescue Errno::EEXIST
          raise ArgumentError,'Managed storage must be a real directory' unless File.directory?(directory) && !File.symlink?(directory)
        end
      end
    end
    def path(actor)
      root=self.root.join("account-#{Integer(actor.id)}")
      directories!(root)
      root.join('reports.jsonl')
    end
    def decode!(file,actor,full:false,task_id:nil)
      file.seek(0,IO::SEEK_END);length=file.pos
      file.seek(full ? 0 : [length-MAX_READ,0].max)
      file.gets if !full && length>MAX_READ # Skip only the incomplete first line of the bounded tail.
      file.each_line.each_with_object({}) do |line,latest|
        value=ReportSchema.validate!(JSON.parse(line))
        raise ArgumentError,'Report journal account mismatch' unless value['account_id']==actor.id
        latest[value.fetch('task_id')]=value if !task_id || value['task_id']==task_id
      end
    rescue JSON::ParserError
      raise ArgumentError,'Malformed structured report journal; manager cannot use this evidence'
    end
    def append!(actor,value)
      ReportSchema.validate!(value,ReportSchema.definition)
      raise ArgumentError,'Report account mismatch' unless value['account_id']==actor.id
      File.open(path(actor),File::RDWR|File::CREAT|File::NOFOLLOW,0600) do |file|
        file.flock(File::LOCK_EX)
        latest=decode!(file,actor)
        unless latest[value['task_id']]==value
          file.seek(0,IO::SEEK_END)
          offset=file.pos
          begin
            file.write(JSON.generate(value)+"\n");file.flush;file.fsync
          rescue IOError,SystemCallError
            # Do not leave a readable new acceptance record after a failed
            # durable append. Preserve the previously committed journal tail.
            begin
              file.truncate(offset);file.flush;file.fsync
            rescue IOError,SystemCallError
              # The original persistence failure remains the blocker.
            end
            raise
          end
        end
      end
      value
    end
    def read!(actor,full:false,task_id:nil)
      target=path(actor)
      return {} unless File.exist?(target)
      File.open(target,File::RDONLY|File::NOFOLLOW) do |file|
        file.flock(File::LOCK_SH)
        decode!(file,actor,full:full || !task_id.nil?,task_id:task_id)
      end
    end
  end
end
