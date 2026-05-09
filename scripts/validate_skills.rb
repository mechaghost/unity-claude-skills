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
  /forward reference — skill in progress/
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
