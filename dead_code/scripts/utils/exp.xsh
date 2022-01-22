from abs import ABC

class Exp(ABC):
    def install_deps(self):
        pass
    
    def cleanup(self):
        pass
    def slowness_inject(self):
        pass
    def init(self):
        pass
    def run(self):
        pass