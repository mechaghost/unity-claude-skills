#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("..", __dir__)
SKILLS_DIR = File.join(ROOT, ".claude", "skills")

errors = []
skill_files = Dir[File.join(SKILLS_DIR, "*", "SKILL.md")].sort

errors << "Expected .claude/skills to exist" unless Dir.exist?(SKILLS_DIR)
errors << "Expected 43 skills, found #{skill_files.length}" unless skill_files.length == 43

skill_files.each do |path|
  rel = path.delete_prefix("#{ROOT}/")
  content = File.read(path)
  frontmatter = content[/\A---\n(.*?)\n---/m, 1]

  if frontmatter.nil?
    errors << "#{rel}: missing YAML frontmatter"
    next
  end

  begin
    parsed = YAML.safe_load(frontmatter)
  rescue Psych::SyntaxError => e
    errors << "#{rel}: invalid YAML frontmatter: #{e.message.lines.first.strip}"
    next
  end

  errors << "#{rel}: missing frontmatter name" unless parsed.is_a?(Hash) && parsed["name"].to_s.match?(/\Aunity-[a-z0-9-]+\z/)
  errors << "#{rel}: missing frontmatter description" unless parsed.is_a?(Hash) && parsed["description"].to_s.start_with?("Use ")

  # The skill set targets Unity 6+ / 6000.x exclusively. Every SKILL.md must
  # state that explicitly somewhere in its body so users on older Unity versions
  # are warned before relying on the skill.
  errors << "#{rel}: must mention 'Unity 6' or '6000.x' (skill set targets Unity 6+ only)" unless content.match?(/Unity 6\b|6000\.x\b/)
end

stale_patterns = [
  /2023\.2 LTS/,
  /Unity 6 \/ 2023\.2/,
  /UnityPurchasing\.Initialize/,
  /IDetailedStoreListener/,
  /IStoreController/,
  /ConfigurationBuilder/,
  /ConfirmPendingPurchase/,
  /full 42 skills/,
  /all 42 skills/,
  /forward reference — skill in progress/,
  # URP 14/15 are pre-Unity-6 versions — the skill set targets URP 17 only.
  /\bURP 14\b/,
  /\bURP 15\b/,
  # Skills must not reference specific MCP tool names — the tool surface
  # changes too fast across competing servers. Describe capabilities instead.
  /`(manage_[a-z_]+|read_console|apply_text_edits|find_gameobjects|create_script|delete_script|validate_script|execute_menu_item|execute_custom_tool|set_active_instance|refresh_unity|run_tests|get_test_job|get_sha|batch_execute|unity_reflect|unity_docs|debug_request_context|script_apply_edits|find_in_file)`/
]

Dir[File.join(ROOT, "{README.md,.claude/skills/**/*.md}")].sort.each do |path|
  rel = path.delete_prefix("#{ROOT}/")
  File.readlines(path).each_with_index do |line, index|
    stale_patterns.each do |pattern|
      errors << "#{rel}:#{index + 1}: stale pattern #{pattern.inspect}" if line.match?(pattern)
    end
  end
end

if errors.empty?
  puts "Skill validation passed: #{skill_files.length} canonical .claude skills"
else
  warn errors.join("\n")
  exit 1
end
