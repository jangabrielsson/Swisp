let __test_lsp = """
(atom 'a)
(eq 'a 'a)
(not (not (not nil)))
(consp '(a))
(not nil)
(not (consp 8))
(equal '(a b c) (list 'a 'b 'c))
"""
