# frozen_string_literal: true
require 'fileutils'
module NevaehOs
  # Only the orchestrator calls this writer. Workers return values, never append files.
  module ReportJournal
    MAX_READ=8*1024*1024
    module_function
    def root = Rails.root.join('storage','nevaeh_worker_reports')
    def directories!(target)
      target.ascend.to_a.reverse_each do |directory|
        raise ArgumentError,'Managed storage cannot contain symbolic links' if File.symlink?(directory)
        Dir.mkdir(directory,0700) unless File.directory?(directory)
      end
    end
    def path(actor)
      root=self.root.join("account-#{Integer(actor.id)}")
      directories!(root)
      root.join('reports.jsonl')
    end
    def decode!(file,actor)
      file.seek(0,IO::SEEK_END);length=file.pos
      file.seek([length-MAX_READ,0].max)
      file.gets if length>MAX_READ # Skip only the incomplete first line of the bounded tail.
      file.each_line.each_with_object({}) do |line,latest|
        value=ReportSchema.validate!(JSON.parse(line))
        raise ArgumentError,'Report journal account mismatch' unless value['account_id']==actor.id
        latest[value.fetch('task_id')]=value
      end
    rescue JSON::ParserError
      raise ArgumentError,'Malformed structured report journal; manager cannot use this evidence'
    end
    def append!(actor,value)
      ReportSchema.validate!(value)
      raise ArgumentError,'Report account mismatch' unless value['account_id']==actor.id
      File.open(path(actor),File::RDWR|File::CREAT|File::NOFOLLOW,0600) do |file|
        file.flock(File::LOCK_EX)
        latest=decode!(file,actor)
        unless latest[value['task_id']]==value
          file.seek(0,IO::SEEK_END)
          file.write(JSON.generate(value)+"\n");file.flush;file.fsync
        end
      end
      value
    end
    def read!(actor)
      target=path(actor)
      return {} unless File.exist?(target)
      File.open(target,File::RDONLY|File::NOFOLLOW) do |file|
        file.flock(File::LOCK_SH)
        decode!(file,actor)
      end
    end
  end
end
