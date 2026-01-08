#!/usr/bin/env ruby
# Script to check the actual error from a failed job
# Run in Rails console: load 'check_job_error.rb'

puts "=" * 80
puts "CHECKING JOB ERROR DETAILS"
puts "=" * 80

# Get the most recent document
doc = Document.order(created_at: :desc).first

if doc.nil?
  puts "\n❌ No documents found!"
  exit
end

puts "\n📄 Document:"
puts "  ID: #{doc.id}"
puts "  Status: #{doc.status}"
puts "  Summary: #{doc.summary ? doc.summary[0..200] : 'nil'}"

# Find the job for this document
job = GoodJob::Job.where("serialized_params::text LIKE ?", "%#{doc.id}%")
                   .where(job_class: "PresentationProcessorJob")
                   .order(created_at: :desc)
                   .first

if job.nil?
  puts "\n❌ No job found for document #{doc.id}"
  exit
end

puts "\n🔍 Job Details:"
puts "  Job ID: #{job.id}"
puts "  ActiveJob ID: #{job.active_job_id}"
puts "  Status: #{job.finished_at ? 'FINISHED' : 'PENDING'}"
puts "  Error in job.error: #{job.error || 'None'}"

# Check GoodJob::Execution for detailed error
execution = GoodJob::Execution.where(active_job_id: job.active_job_id).order(created_at: :desc).first

if execution.nil?
  puts "\n❌ No execution record found"
else
  puts "\n📋 Execution Details:"
  puts "  Execution ID: #{execution.id}"
  puts "  Created: #{execution.created_at}"
  puts "  Finished: #{execution.finished_at || 'Not finished'}"
  puts "  Duration: #{execution.duration}"
  
  if execution.error.present?
    puts "\n  ❌ ERROR FOUND:"
    puts "  #{execution.error[0..500]}"
    
    if execution.error_backtrace.present?
      puts "\n  📍 Backtrace (first 10 lines):"
      execution.error_backtrace.first(10).each_with_index do |line, idx|
        puts "    #{idx + 1}. #{line}"
      end
    end
  else
    puts "\n  ⚠️  No error in execution record (check document.summary or Rails logs)"
  end
end

puts "\n" + "=" * 80
