// jogger: a searchable, navigable TUI for your shell aliases.
//
// Aliases are parsed from the shellAliases block in /etc/nixos/zsh.nix and
// mirrored into ~/.config/jogger.toml, where you can write your own
// descriptions. New aliases are picked up automatically on every run.
//
//	go mod init jogger && go mod tidy
//	go run .
//
// Flags:
//
//	-nix    path to the Nix file   (default /etc/nixos/zsh.nix)
//	-config path to jogger's file  (default ~/.config/jogger.toml)
//
// Keys: type to search • ↑/↓ PgUp/PgDn move • enter run • ctrl+e edit command
// first (e.g. to add arguments) • tab show/hide commented-out aliases •
// esc clear search / quit • ctrl+c quit.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"

	"github.com/BurntSushi/toml"
	"github.com/charmbracelet/bubbles/table"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

type entry struct {
	Name        string `toml:"name"`
	Command     string `toml:"command"`
	Description string `toml:"description"`
	Category    string `toml:"category"`
	Disabled    bool   `toml:"disabled"` // commented out in the Nix file
}

type storeFile struct {
	Alias []entry `toml:"alias"`
}

// Descriptions used to seed brand-new entries that have none yet. Aliases not
// listed here start with an empty description for you to fill in.
var defaultDescriptions = map[string]string{
	"nrs":      "Rebuild, upgrade inputs, and switch to the new config",
	"nrt":      "Build and activate the config without making it the boot default",
	"nrb":      "Build the config and set it as the next boot default (no live switch)",
	"cfg":      "Open the NixOS config directory in your editor",
	"ns":       "Search nixpkgs (stable) for a package",
	"nsp":      "Drop into a temporary shell with the given package(s)",
	"nsu":      "Search nixpkgs-unstable for a package",
	"ngc":      "Delete old generations and garbage-collect the Nix store",
	"nlo":      "List packages installed in your Nix profile",
	"rebuild":  "Rebuild and switch to the runabout flake config",
	"update":   "Run the system update script in /etc/nixos",
	"g":        "Shorthand for git",
	"ga":       "Stage specific files",
	"gaa":      "Stage all changes (new, modified, deleted)",
	"gc":       "Commit staged changes (opens editor)",
	"gcm":      "Commit staged changes with an inline message",
	"gca":      "Amend the previous commit",
	"gco":      "Switch branches or restore files",
	"gcb":      "Create and switch to a new branch",
	"gd":       "Show unstaged changes",
	"gds":      "Show staged changes",
	"gl":       "Compact commit graph for the current branch",
	"gla":      "Compact commit graph across all branches",
	"gp":       "Push commits to the remote",
	"gpf":      "Force-push, but abort if the remote has commits you haven't seen",
	"gpl":      "Fetch and merge from the remote",
	"gst":      "Show working tree status",
	"gstash":   "Stash uncommitted changes",
	"gpop":     "Reapply the most recent stash and drop it",
	"gr":       "List remotes with their URLs",
	"grb":      "Rebase the current branch onto another",
	"gri":      "Interactive rebase (reorder, squash, edit commits)",
	"grs":      "Discard working tree changes to a file",
	"grss":     "Unstage a file, keeping its changes",
	"gcp":      "Apply a specific commit onto the current branch",
	"..":       "Go up one directory",
	"...":      "Go up two directories",
	"....":     "Go up three directories",
	"ll":       "Long listing, all files, human-readable sizes",
	"la":       "List all files except . and ..",
	"l":        "Columnar listing with type indicators (/ * @)",
	"makemine": "Recursively take ownership of a path for your user and group",
	"mkdir":    "Create directories, including missing parents",
	"cp":       "Copy, prompting before overwrite, with verbose output",
	"mv":       "Move/rename, prompting before overwrite, with verbose output",
	"rm":       "Remove, prompting for each file, with verbose output",
	"df":       "Disk free space, human-readable",
	"du":       "Summarized size of a path, human-readable",
	"free":     "Memory usage, human-readable",
	"grep":     "grep with colored matches",
	"p":        "Launch Python 3",
	"vi":       "Open Neovim",
	"vim":      "Open Neovim",
	"v":        "Open Neovim",
	"y":        "Open the yazi terminal file manager",
	"yz":       "Open the yazi terminal file manager",
	"zshrc":    "Edit your zsh config",
	"vimrc":    "Edit your Neovim config",
}

// ---------------------------------------------------------------------------
// Nix parsing
// ---------------------------------------------------------------------------

var (
	// `shellAliases = {`, `programs.zsh.shellAliases = lib.mkForce {`, etc.
	blockStartRe = regexp.MustCompile(`shellAliases[^=\n]*=[^{\n]*\{`)
	// `# --- Git ---`
	headerRe = regexp.MustCompile(`^\s*#\s*-{2,}\s*(.*?)\s*-{2,}\s*$`)
	// `  gcm = "git commit -m";`  /  `  ".." = "cd ..";`  /  `  #nrs = "...";  # note`
	//  1: leading '#' (disabled)  2: quoted name  3: bare name  4: value  5: trailing comment
	aliasRe = regexp.MustCompile(
		`^\s*(#\s*)?(?:"([^"]+)"|([A-Za-z_][A-Za-z0-9_'-]*))\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*(?:#\s*(.*?))?\s*$`)
	strLitRe = regexp.MustCompile(`"(?:[^"\\]|\\.)*"`)
)

// braceDelta returns (#{ - #}) on a line, ignoring string contents and comments.
func braceDelta(line string) int {
	line = strLitRe.ReplaceAllString(line, `""`)
	if i := strings.Index(line, "#"); i >= 0 {
		line = line[:i]
	}
	return strings.Count(line, "{") - strings.Count(line, "}")
}

func nixUnescape(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			i++
			switch s[i] {
			case 'n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			case 'r':
				b.WriteByte('\r')
			default:
				b.WriteByte(s[i])
			}
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// parseNix extracts aliases (active and commented-out) from the shellAliases
// block. If no such block exists, the whole file is scanned.
func parseNix(src string) []entry {
	hasBlock := blockStartRe.MatchString(src)
	inBlock := !hasBlock
	depth := 0
	category := ""

	var out []entry
	index := map[string]int{}

	for _, line := range strings.Split(src, "\n") {
		if !inBlock {
			if blockStartRe.MatchString(line) {
				depth = braceDelta(line)
				inBlock = depth > 0
				category = ""
			}
			continue
		}

		if m := headerRe.FindStringSubmatch(line); m != nil {
			category = m[1]
		} else if m := aliasRe.FindStringSubmatch(line); m != nil {
			name := m[2]
			if name == "" {
				name = m[3]
			}
			e := entry{
				Name:        name,
				Command:     nixUnescape(m[4]),
				Description: strings.TrimSpace(m[5]),
				Category:    category,
				Disabled:    strings.TrimSpace(m[1]) != "",
			}
			if i, dup := index[name]; dup {
				// An active definition beats a commented-out one.
				if out[i].Disabled && !e.Disabled {
					out[i] = e
				}
			} else {
				index[name] = len(out)
				out = append(out, e)
			}
		}

		if hasBlock {
			depth += braceDelta(line)
			if depth <= 0 {
				inBlock = false
			}
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// jogger.toml storage + sync
// ---------------------------------------------------------------------------

func defaultConfigPath() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(dir, "jogger.toml")
}

func readStore(path string) ([]entry, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var sf storeFile
	if _, err := toml.Decode(string(data), &sf); err != nil {
		return nil, err
	}
	return sf.Alias, nil
}

func tomlStr(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '\\':
			b.WriteString(`\\`)
		case '"':
			b.WriteString(`\"`)
		case '\n':
			b.WriteString(`\n`)
		case '\t':
			b.WriteString(`\t`)
		case '\r':
			b.WriteString(`\r`)
		default:
			if r < 0x20 || r == 0x7f {
				fmt.Fprintf(&b, `\u%04X`, r)
			} else {
				b.WriteRune(r)
			}
		}
	}
	b.WriteByte('"')
	return b.String()
}

func renderStore(entries []entry, nixPath string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# jogger alias list\n#\n")
	fmt.Fprintf(&b, "# Synced from %s every time jogger runs.\n", nixPath)
	b.WriteString("# Edit `description` freely. name, command, category and disabled are\n")
	b.WriteString("# overwritten from the Nix file, and comments added here are not preserved.\n")

	last := "\x00"
	for _, e := range entries {
		if e.Category != last {
			label := e.Category
			if label == "" {
				label = "Uncategorized"
			}
			fmt.Fprintf(&b, "\n# ---------- %s ----------\n", label)
			last = e.Category
		}
		b.WriteString("\n[[alias]]\n")
		fmt.Fprintf(&b, "name        = %s\n", tomlStr(e.Name))
		fmt.Fprintf(&b, "command     = %s\n", tomlStr(e.Command))
		fmt.Fprintf(&b, "description = %s\n", tomlStr(e.Description))
		fmt.Fprintf(&b, "category    = %s\n", tomlStr(e.Category))
		if e.Disabled {
			b.WriteString("disabled    = true\n")
		}
	}
	return b.String()
}

func writeIfChanged(path, content string) error {
	if old, err := os.ReadFile(path); err == nil && string(old) == content {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(content), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

type syncStats struct {
	added   []string
	removed int
	updated int
}

// syncEntries treats the Nix file as the source of truth for everything except
// descriptions, which are kept from the stored file.
func syncEntries(parsed, stored []entry) ([]entry, syncStats) {
	old := make(map[string]entry, len(stored))
	for _, s := range stored {
		old[s.Name] = s
	}
	seen := make(map[string]bool, len(parsed))
	var st syncStats
	out := make([]entry, 0, len(parsed))

	for _, p := range parsed {
		seen[p.Name] = true
		if s, ok := old[p.Name]; ok {
			if s.Command != p.Command || s.Category != p.Category || s.Disabled != p.Disabled {
				st.updated++
			}
			if strings.TrimSpace(s.Description) != "" {
				p.Description = s.Description
			}
		} else {
			st.added = append(st.added, p.Name)
			if p.Description == "" {
				p.Description = defaultDescriptions[p.Name]
			}
		}
		out = append(out, p)
	}
	for _, s := range stored {
		if !seen[s.Name] {
			st.removed++
		}
	}
	return out, st
}

// load reads the Nix file and jogger.toml, merges them, and writes the result
// back if anything changed. It returns the entries to display and a status
// message for the header.
func load(nixPath, cfgPath string) (entries []entry, msg string, isErr bool) {
	stored, storeErr := readStore(cfgPath)
	created := storeErr == nil && len(stored) == 0

	src, err := os.ReadFile(nixPath)
	if err != nil {
		return stored, fmt.Sprintf("can't read %s (%v) — showing saved list", nixPath, err), true
	}
	parsed := parseNix(string(src))
	if len(parsed) == 0 {
		return stored, fmt.Sprintf("no aliases found in %s — showing saved list", nixPath), true
	}

	merged, st := syncEntries(parsed, stored)

	if storeErr != nil {
		return merged, fmt.Sprintf("%s is invalid (%v) — not overwriting it", cfgPath, firstLine(storeErr.Error())), true
	}
	if err := writeIfChanged(cfgPath, renderStore(merged, nixPath)); err != nil {
		return merged, fmt.Sprintf("couldn't write %s: %v", cfgPath, err), true
	}

	switch {
	case created:
		msg = fmt.Sprintf("created %s with %d aliases", cfgPath, len(merged))
	case len(st.added) > 0 || st.removed > 0 || st.updated > 0:
		var parts []string
		if n := len(st.added); n > 0 {
			names := st.added
			suffix := ""
			if n > 5 {
				names, suffix = names[:5], ", …"
			}
			parts = append(parts, fmt.Sprintf("+%d new (%s%s)", n, strings.Join(names, ", "), suffix))
		}
		if st.updated > 0 {
			parts = append(parts, fmt.Sprintf("%d updated", st.updated))
		}
		if st.removed > 0 {
			parts = append(parts, fmt.Sprintf("%d removed", st.removed))
		}
		msg = "synced: " + strings.Join(parts, ", ")
	}
	return merged, msg, false
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

var (
	accent = lipgloss.Color("212")
	muted  = lipgloss.Color("241")
	subtle = lipgloss.Color("245")

	titleStyle  = lipgloss.NewStyle().Bold(true).Foreground(accent)
	countStyle  = lipgloss.NewStyle().Foreground(muted)
	statusStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("114"))
	errStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("203"))
	helpStyle   = lipgloss.NewStyle().Foreground(muted)
	detailBox   = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(muted).Padding(0, 1)
	detailName  = lipgloss.NewStyle().Bold(true).Foreground(accent)
	detailCmd   = lipgloss.NewStyle().Foreground(lipgloss.Color("86"))
	detailDesc  = lipgloss.NewStyle().Foreground(subtle)
	detailEmpty = lipgloss.NewStyle().Foreground(muted).Italic(true)
)

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

type mode int

const (
	modeBrowse mode = iota
	modeEdit
)

type model struct {
	all     []entry
	visible []entry // entries currently shown, parallel to table rows

	search textinput.Model
	edit   textinput.Model
	table  table.Model
	mode   mode

	showDisabled  bool
	width, height int

	cfgPath   string
	status    string
	statusErr bool

	run string // command to execute after the TUI exits
}

func newModel(all []entry, cfgPath, status string, statusErr bool) model {
	ti := textinput.New()
	ti.Prompt = "/ "
	ti.PromptStyle = lipgloss.NewStyle().Foreground(accent)
	ti.Placeholder = "search aliases, commands, descriptions…"
	ti.CharLimit = 80
	ti.Focus()

	ed := textinput.New()
	ed.Prompt = "$ "
	ed.PromptStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("86"))
	ed.CharLimit = 0

	ts := table.DefaultStyles()
	ts.Header = ts.Header.
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(muted).
		BorderBottom(true).
		Bold(true).
		Foreground(accent)
	ts.Selected = lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("230")).
		Background(lipgloss.Color("57"))

	t := table.New(
		table.WithColumns([]table.Column{
			{Title: "ALIAS", Width: 14},
			{Title: "COMMAND", Width: 40},
			{Title: "DESCRIPTION", Width: 40},
		}),
		table.WithFocused(true),
		table.WithStyles(ts),
	)

	m := model{
		all: all, search: ti, edit: ed, table: t,
		width: 100, height: 30,
		cfgPath: cfgPath, status: firstLine(status), statusErr: statusErr,
	}
	m.resize()
	m.applyFilter()
	return m
}

// score ranks how well an entry matches the search terms (lower is better).
func score(e entry, terms []string) int {
	if len(terms) == 0 {
		return 0
	}
	name := strings.ToLower(e.Name)
	best := 3
	for _, t := range terms {
		switch {
		case name == t:
			best = min(best, 0)
		case strings.HasPrefix(name, t):
			best = min(best, 1)
		case strings.Contains(name, t):
			best = min(best, 2)
		}
	}
	return best
}

func (m *model) applyFilter() {
	terms := strings.Fields(strings.ToLower(m.search.Value()))

	var matched []entry
	for _, e := range m.all {
		if e.Disabled && !m.showDisabled {
			continue
		}
		hay := strings.ToLower(e.Name + " " + e.Command + " " + e.Description + " " + e.Category)
		ok := true
		for _, t := range terms {
			if !strings.Contains(hay, t) {
				ok = false
				break
			}
		}
		if ok {
			matched = append(matched, e)
		}
	}

	if len(terms) > 0 {
		sort.SliceStable(matched, func(i, j int) bool {
			return score(matched[i], terms) < score(matched[j], terms)
		})
	}

	rows := make([]table.Row, 0, len(matched))
	for _, e := range matched {
		name := e.Name
		if e.Disabled {
			name += " (off)"
		}
		desc := e.Description
		if desc == "" {
			desc = "—"
		}
		rows = append(rows, table.Row{name, e.Command, desc})
	}

	m.visible = matched
	m.table.SetRows(rows)
	m.table.SetCursor(0)
}

func (m *model) resize() {
	// Header and cell styles each add 1 column of padding on both sides.
	const padding = 2
	const nameW = 14
	avail := m.width - 2 - 3*padding - nameW
	if avail < 20 {
		avail = 20
	}
	cmdW := avail * 45 / 100
	descW := avail - cmdW

	m.table.SetColumns([]table.Column{
		{Title: "ALIAS", Width: nameW},
		{Title: "COMMAND", Width: cmdW},
		{Title: "DESCRIPTION", Width: descW},
	})
	m.table.SetWidth(m.width - 2)

	// title(1) + input(1) + detail box(5) + help(1) + margin(1)
	h := m.height - 9
	if h < 5 {
		h = 5
	}
	m.table.SetHeight(h)

	m.search.Width = m.width - 6
	m.edit.Width = m.width - 6
}

func (m model) selected() (entry, bool) {
	i := m.table.Cursor()
	if i < 0 || i >= len(m.visible) {
		return entry{}, false
	}
	return m.visible[i], true
}

func (m model) Init() tea.Cmd { return textinput.Blink }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.resize()
		return m, nil

	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}

		// --- edit-before-run mode ---
		if m.mode == modeEdit {
			switch msg.String() {
			case "esc":
				m.mode = modeBrowse
				m.edit.Blur()
				return m, m.search.Focus()
			case "enter":
				if cmd := strings.TrimSpace(m.edit.Value()); cmd != "" {
					m.run = cmd
					return m, tea.Quit
				}
				return m, nil
			}
			var cmd tea.Cmd
			m.edit, cmd = m.edit.Update(msg)
			return m, cmd
		}

		// --- browse mode ---
		page := m.table.Height() - 2
		if page < 1 {
			page = 1
		}
		switch msg.String() {
		case "esc":
			if m.search.Value() != "" {
				m.search.SetValue("")
				m.applyFilter()
				return m, nil
			}
			return m, tea.Quit
		case "enter":
			if e, ok := m.selected(); ok {
				m.run = e.Command
				return m, tea.Quit
			}
			return m, nil
		case "ctrl+e":
			if e, ok := m.selected(); ok {
				m.mode = modeEdit
				m.search.Blur()
				m.edit.SetValue(e.Command + " ")
				m.edit.CursorEnd()
				return m, m.edit.Focus()
			}
			return m, nil
		case "tab":
			m.showDisabled = !m.showDisabled
			m.applyFilter()
			return m, nil
		case "up", "ctrl+p":
			m.table.MoveUp(1)
			return m, nil
		case "down", "ctrl+n":
			m.table.MoveDown(1)
			return m, nil
		case "pgup":
			m.table.MoveUp(page)
			return m, nil
		case "pgdown":
			m.table.MoveDown(page)
			return m, nil
		case "ctrl+home":
			m.table.GotoTop()
			return m, nil
		case "ctrl+end":
			m.table.GotoBottom()
			return m, nil
		}
	}

	// Everything else (typing, cursor blink, …) goes to the active text input.
	var cmd tea.Cmd
	if m.mode == modeEdit {
		m.edit, cmd = m.edit.Update(msg)
		return m, cmd
	}
	before := m.search.Value()
	m.search, cmd = m.search.Update(msg)
	if m.search.Value() != before {
		m.applyFilter()
	}
	return m, cmd
}

func (m model) detailView() string {
	inner := m.width - 6 // border (2) + padding (2) + slack
	if inner < 10 {
		inner = 10
	}
	box := detailBox.Width(m.width - 2).Height(3)

	e, ok := m.selected()
	if !ok {
		return box.Render(detailDesc.Render("No matching aliases."))
	}

	head := detailName.Render(e.Name)
	if e.Disabled {
		head += countStyle.Render("  (commented out in config)")
	}
	cmd := detailCmd.Width(inner).Render("→ " + e.Command)

	var desc string
	if e.Description == "" {
		desc = detailEmpty.Width(inner).Render("no description — add one in " + m.cfgPath)
	} else {
		desc = detailDesc.Width(inner).Render(e.Description)
	}
	return box.Render(head + "\n" + cmd + "\n" + desc)
}

func (m model) View() string {
	total := 0
	for _, e := range m.all {
		if !e.Disabled || m.showDisabled {
			total++
		}
	}

	title := titleStyle.Render("jogger") + "  " +
		countStyle.Render(fmt.Sprintf("%d/%d", len(m.visible), total))
	if m.status != "" {
		st := statusStyle
		if m.statusErr {
			st = errStyle
		}
		title += "  " + st.Render(m.status)
	}
	title = lipgloss.NewStyle().MaxWidth(m.width).Render(title)

	input := m.search.View()
	toggle := "show disabled"
	if m.showDisabled {
		toggle = "hide disabled"
	}
	help := fmt.Sprintf("enter run • ctrl+e edit first • ↑/↓ pgup/pgdn • tab %s • esc clear/quit", toggle)

	if m.mode == modeEdit {
		input = m.edit.View()
		help = "editing command — enter run • esc cancel • ctrl+c quit"
	}
	help = helpStyle.MaxWidth(m.width).Render(help)

	return strings.Join([]string{
		title,
		input,
		m.table.View(),
		m.detailView(),
		help,
	}, "\n")
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

// runCommand replaces the jogger process with `$SHELL -c <cmdline>` so the
// command gets the terminal, signals, and exit code exactly as if typed.
func runCommand(cmdline string) {
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/sh"
	}
	path, err := exec.LookPath(shell)
	if err != nil {
		shell = "/bin/sh"
		path = shell
	}
	fmt.Fprintf(os.Stderr, "$ %s\n", cmdline)
	err = syscall.Exec(path, []string{filepath.Base(shell), "-c", cmdline}, os.Environ())
	fmt.Fprintln(os.Stderr, "jogger: exec failed:", err)
	os.Exit(1)
}

func main() {
	nixPath := flag.String("nix", "/etc/nixos/zsh.nix", "Nix file containing the shellAliases block")
	cfgPath := flag.String("config", defaultConfigPath(), "jogger's alias/description file")
	flag.Parse()

	all, status, isErr := load(*nixPath, *cfgPath)

	final, err := tea.NewProgram(newModel(all, *cfgPath, status, isErr), tea.WithAltScreen()).Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "jogger:", err)
		os.Exit(1)
	}
	if fm, ok := final.(model); ok && fm.run != "" {
		runCommand(fm.run)
	}
}
