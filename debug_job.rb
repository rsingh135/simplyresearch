#!/usr/bin/env ruby
# Debugging script to check job status and document processing
# Run this in Rails console: load 'debug_job.rb'

puts "=" * 80
puts "JOB DEBUGGING SCRIPT"
puts "=" * 80

# Get the most recent document
document = Document.order(created_at: :desc).first

if document.nil?
  puts "\n❌ ERROR: No documents found in database!"
  exit
end

puts "\n📄 Document Info:"
puts "  ID: #{document.id}"
puts "  Title: #{document.title || '(no title)'}"
puts "  Status: #{document.status || 'nil'}"
puts "  PDF Attached: #{document.pdf.attached?}"
puts "  Created: #{document.created_at}"
puts "  Updated: #{document.updated_at}"

# Check GoodJob records
puts "\n🔍 Checking GoodJob records..."
jobs = GoodJob::Job.where("serialized_params::text LIKE ?", "%#{document.id}%").order(created_at: :desc).limit(5)

if jobs.empty?
  puts "  ⚠️  No jobs found for this document!"
  puts "  This means the job was never enqueued or the job_id doesn't match."
else
  jobs.each_with_index do |job, index|
    puts "\n  Job ##{index + 1}:"
    puts "    Job ID: #{job.id}"
    puts "    ActiveJob ID: #{job.active_job_id}"
    puts "    Job Class: #{job.job_class}"
    puts "    Status: #{job.finished_at ? 'FINISHED' : (job.locked_at ? 'RUNNING' : 'PENDING')}"
    puts "    Created: #{job.created_at}"
    puts "    Performed: #{job.performed_at || 'Not yet'}"
    puts "    Finished: #{job.finished_at || 'Not yet'}"
    
    if job.error.present?
      puts "    ❌ ERROR: #{job.error[0..200]}"
    end
    
    # Check executions
    executions = GoodJob::Execution.where(active_job_id: job.active_job_id)
    if executions.any?
      puts "    Executions: #{executions.count}"
      executions.order(created_at: :desc).limit(3).each do |exec|
        puts "      - Created: #{exec.created_at}, Finished: #{exec.finished_at || 'No'}"
        if exec.error.present?
          puts "        ERROR: #{exec.error[0..200]}"
        end
      end
    end
  end
end

# Check if GoodJob processes are running
puts "\n🔄 Checking GoodJob processes..."
processes = GoodJob::Process.all
if processes.empty?
  puts "  ⚠️  WARNING: No GoodJob processes found!"
  puts "  This means GoodJob is NOT running. You need to start it."
else
  processes.each do |process|
    puts "  Process ID: #{process.id}"
    puts "    Created: #{process.created_at}"
    puts "    State: #{process.state}"
  end
end

# Check for pending jobs
puts "\n⏳ Checking pending jobs..."
pending = GoodJob::Job.where(finished_at: nil).where("job_class = ?", "PresentationProcessorJob")
if pending.any?
  puts "  Found #{pending.count} pending PresentationProcessorJob(s):"
  pending.each do |job|
    puts "    - Job ID: #{job.id}, Created: #{job.created_at}"
  end
else
  puts "  ✓ No pending PresentationProcessorJob found"
end

# Check for failed jobs
puts "\n❌ Checking failed jobs..."
failed = GoodJob::Job.where.not(error: nil).where("job_class = ?", "PresentationProcessorJob").order(created_at: :desc).limit(5)
if failed.any?
  puts "  Found #{failed.count} failed PresentationProcessorJob(s):"
  failed.each do |job|
    puts "    - Job ID: #{job.id}"
    puts "      Error: #{job.error[0..300]}"
    puts "      Created: #{job.created_at}"
  end
else
  puts "  ✓ No failed PresentationProcessorJob found"
end

puts "\n" + "=" * 80
puts "Debugging complete!"
puts "=" * 80
