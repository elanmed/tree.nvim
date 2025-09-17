.PHONY: dev clean test lint docs

dev:
	mkdir -p ~/.local/share/nvim/site/pack/dev/start/tree.nvim
	stow -d .. -t ~/.local/share/nvim/site/pack/dev/start/tree.nvim tree.nvim

clean:
	rm -rf ~/.local/share/nvim/site/pack/dev

test:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

lint: 
	# https://luals.github.io/#install
	lua-language-server --check=./lua --checklevel=Error

docs: 
	./deps/ts-vimdoc.nvim/scripts/docgen.sh README.md doc/tree.txt tree
	nvim --headless -c "helptags doc/" -c "qa"

deploy: test lint docs
